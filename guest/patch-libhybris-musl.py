#!/usr/bin/env python3
"""Apply Determination's narrow musl host-libc adapters to libhybris.

The Android side is still bionic.  These changes only replace glibc-specific
host calls and private layouts used by hybris/common.  The patch is deliberately
source-pinned and fails on a missing anchor instead of guessing at a new tree.
"""

from __future__ import annotations

import pathlib
import sys


MARKER = "Determination musl host adapters"


def replace_once(text: str, old: str, new: str, path: pathlib.Path) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"musl patch anchor count {count}, expected 1: {path}")
    return text.replace(old, new, 1)


def patch_linker_mutexes(common: pathlib.Path) -> None:
    stock = "static pthread_mutex_t g_dl_mutex = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;"
    replacement = r"""\
static pthread_mutex_t g_dl_mutex;
static pthread_once_t g_dl_mutex_once = PTHREAD_ONCE_INIT;

static void hybris_init_dl_mutex() {
  pthread_mutexattr_t attr;
  pthread_mutexattr_init(&attr);
  pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
  pthread_mutex_init(&g_dl_mutex, &attr);
  pthread_mutexattr_destroy(&attr);
}

static pthread_mutex_t* hybris_dl_mutex() {
  pthread_once(&g_dl_mutex_once, hybris_init_dl_mutex);
  return &g_dl_mutex;
}"""
    for variant in ("mm", "n", "o", "q"):
        path = common / variant / "dlfcn.cpp"
        text = path.read_text()
        if "hybris_init_dl_mutex" in text:
            continue
        text = replace_once(text, stock, replacement, path)
        text = text.replace(
            "ScopedPthreadMutexLocker locker(&g_dl_mutex);",
            "ScopedPthreadMutexLocker locker(hybris_dl_mutex());",
        )
        path.write_text(text)
        print(f"musl recursive mutex: patched {path}")


def patch_basename(common: pathlib.Path) -> None:
    for path in common.rglob("*.cpp"):
        text = path.read_text()
        if "basename(" not in text or "hybris_musl_basename" in text:
            continue
        text = text.replace("basename(", "hybris_musl_basename(")
        first_include = text.find("#include ")
        if first_include < 0:
            raise SystemExit(f"basename include anchor missing: {path}")
        helper = """#include <libgen.h>
static inline char* hybris_musl_basename(const char* path) {
  return basename(const_cast<char*>(path));
}
"""
        if "#include <libgen.h>\n" in text:
            text = text.replace("#include <libgen.h>\n", helper, 1)
        else:
            text = text[:first_include] + helper + text[first_include:]
        path.write_text(text)
        print(f"musl basename declaration: patched {path}")


def patch_embedded_tls_lifecycle(common: pathlib.Path) -> None:
    main_path = common / "q" / "linker_main.cpp"
    main_text = main_path.read_text()
    obsolete = """  /* Determination: embedded linker has no initial static TLS image. The
   * normal PT_INTERP path finalizes this layout before dlopen; hybris' entry
   * point must do the same or every bionic DSO is misclassified as static TLS
   * and CHECK-aborts when a short-lived loader client closes it. */
  linker_finalize_static_tls();
"""
    if obsolete in main_text:
        main_path.write_text(main_text.replace(obsolete, "", 1))
        print(f"musl embedded TLS lifecycle: removed dynamic-only experiment from {main_path}")

    path = common / "q" / "linker_tls.cpp"
    text = path.read_text()
    marker = "Determination: a static-TLS DSO cannot be safely unloaded"
    if marker in text:
        print(f"musl embedded TLS pinning: already patched {path}")
    else:
        old = """  g_tls_modules[module_idx].first_generation = new_generation;
  g_tls_modules[module_idx].soinfo_ptr = si;
}"""
        new = """  g_tls_modules[module_idx].first_generation = new_generation;
  g_tls_modules[module_idx].soinfo_ptr = si;
  /* Determination: a static-TLS DSO cannot be safely unloaded. Android's
   * normal linker never does so; pin the same modules in the embedded hybris
   * linker instead of reaching unregister_tls_module's deliberate CHECK. */
  if (static_offset != SIZE_MAX)
    si->set_nodelete();
}"""
        text = replace_once(text, old, new, path)
        path.write_text(text)
        print(f"musl embedded TLS pinning: patched {path}")

    unload_path = common / "q" / "linker.cpp"
    unload_text = unload_path.read_text()
    partial_unload = """        } else if (child->get_parents().empty()) {
          /* Determination: retain a pinned NODELETE dependency even when its
           * unloadable group root closes. Static-TLS bionic DSOs are pinned
           * above because unregistering them would invalidate IE TLS. */
          if (child->can_unload())
            unload_list.push_back(child);
        }"""
    if partial_unload in unload_text:
        unload_text = unload_text.replace(
            partial_unload,
            """        } else if (child->get_parents().empty()) {
          unload_list.push_back(child);
        }""",
            1,
        )
        print(f"musl NODELETE group pinning: removed partial-unload experiment from {unload_path}")

    group_marker = "Determination: static TLS pins the complete local load group"
    if group_marker in unload_text:
        print(f"musl NODELETE group pinning: already patched {unload_path}")
        unload_path.write_text(unload_text)
        return
    old = """    if (!linked) {
      return false;
    }
  }

  // Step 7"""
    new = """    if (!linked) {
      return false;
    }

    /* Determination: static TLS pins the complete local load group. Retaining
     * only the Initial-Exec TLS DSO leaves its dependency graph pointing at
     * unloaded parents, which makes a successful hybris_dlclose segfault on
     * return. Android treats the group as one lifetime for this purpose. */
    bool group_has_nodelete = false;
    local_group.visit([&](soinfo* si) {
      if ((si->get_rtld_flags() & RTLD_NODELETE) != 0) {
        group_has_nodelete = true;
      }
      return true;
    });
    if (group_has_nodelete) {
      root->set_nodelete();
    }
  }

  // Step 7"""
    unload_text = replace_once(unload_text, old, new, unload_path)
    unload_path.write_text(unload_text)
    print(f"musl NODELETE group pinning: patched {unload_path}")


def patch_hooks(common: pathlib.Path) -> None:
    path = common / "hooks.c"
    text = path.read_text()
    # This second-stage shim is intentionally applied before the core marker
    # check so an existing musl build tree can be resumed after discovering a
    # later link-only libc gap.
    fortify_old = "ret = __vsprintf_chk (__s, __flag, __slen, __format, args);"
    if fortify_old in text:
        text = replace_once(
            text,
            fortify_old,
            """(void)__flag;
    ret = vsnprintf(__s, __slen, __format, args);""",
            path,
        )
        text = replace_once(
            text,
            "ret = __vsnprintf_chk (__s, __n, __flag, __slen, __format, args);",
            """(void)__flag;
    if (__n > __slen)
        __n = __slen;
    ret = vsnprintf(__s, __n, __format, args);""",
            path,
        )
        path.write_text(text)
        print(f"musl fortify hooks: patched {path}")
    if MARKER in text:
        print(f"musl host hooks: already patched {path}")
        return

    helper_anchor = """// this is also used in bionic:
#define bool int
"""
    helpers = r"""// this is also used in bionic:
#define bool int

/* Determination musl host adapters.  Keep bionic-facing names and ABIs while
 * avoiding glibc-only symbols and private FILE/pthread layouts. */
struct hybris_musl_mallinfo {
    size_t arena, ordblks, smblks, hblks, hblkhd;
    size_t usmblks, fsmblks, uordblks, fordblks, keepcost;
};

static struct hybris_musl_mallinfo _hybris_musl_mallinfo(void)
{
    struct hybris_musl_mallinfo info = {0};
    return info;
}

static void *_hybris_musl_pvalloc(size_t size)
{
    long page_value = sysconf(_SC_PAGESIZE);
    size_t page;
    size_t rounded;
    void *result = NULL;
    int rc;

    if (page_value <= 0) {
        errno = EINVAL;
        return NULL;
    }
    page = (size_t)page_value;
    if (size == 0)
        rounded = page;
    else {
        if (size > SIZE_MAX - (page - 1)) {
            errno = ENOMEM;
            return NULL;
        }
        rounded = (size + page - 1) / page * page;
    }
    rc = posix_memalign(&result, page, rounded);
    if (rc != 0) {
        errno = rc;
        return NULL;
    }
    return result;
}

static wchar_t *_hybris_musl_wmempcpy(wchar_t *dest, const wchar_t *src,
                                      size_t count)
{
    wmemcpy(dest, src, count);
    return dest + count;
}

static int _hybris_musl_clock_deadline(clockid_t clock_id,
                                       const struct timespec *abstime,
                                       struct timespec *realtime)
{
    struct timespec clock_now;
    struct timespec realtime_now;
    time_t seconds;
    long nanoseconds;

    if (clock_id == CLOCK_REALTIME) {
        *realtime = *abstime;
        return 0;
    }
    if (clock_id != CLOCK_MONOTONIC)
        return EINVAL;
    if (clock_gettime(clock_id, &clock_now) != 0 ||
        clock_gettime(CLOCK_REALTIME, &realtime_now) != 0)
        return errno;

    seconds = abstime->tv_sec - clock_now.tv_sec;
    nanoseconds = abstime->tv_nsec - clock_now.tv_nsec;
    if (nanoseconds < 0) {
        seconds--;
        nanoseconds += 1000000000L;
    }
    if (seconds < 0) {
        *realtime = realtime_now;
        return 0;
    }
    realtime->tv_sec = realtime_now.tv_sec + seconds;
    realtime->tv_nsec = realtime_now.tv_nsec + nanoseconds;
    if (realtime->tv_nsec >= 1000000000L) {
        realtime->tv_sec++;
        realtime->tv_nsec -= 1000000000L;
    }
    return 0;
}

struct hybris_musl_rwlockattr {
    pthread_rwlockattr_t attr; /* first: existing casts remain valid */
    int kind;
};

#define HYBRIS_RWLOCK_PREFER_READER_NP 0
#define HYBRIS_RWLOCK_PREFER_WRITER_NP 1
#define HYBRIS_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP 2
"""
    text = replace_once(text, helper_anchor, helpers, path)

    old = """    return pthread_attr_setstackaddr(realattr, stack_addr);
}"""
    new = """    size_t stack_size;
    void *stack_base;
    int rc = pthread_attr_getstack(realattr, &stack_base, &stack_size);
    if (rc != 0)
        return rc;
    /* glibc/bionic's obsolete API takes the top of a downward-growing stack;
     * pthread_attr_setstack takes its lowest address. Determination is arm64. */
    return pthread_attr_setstack(realattr, (char *)stack_addr - stack_size,
                                 stack_size);
}"""
    text = replace_once(text, old, new, path)

    old = """    return pthread_attr_getstackaddr(realattr, stack_addr);
}"""
    new = """    size_t stack_size;
    void *stack_base;
    int rc = pthread_attr_getstack(realattr, &stack_base, &stack_size);
    if (rc == 0)
        *stack_addr = (char *)stack_base + stack_size;
    return rc;
}"""
    text = replace_once(text, old, new, path)

    text = replace_once(
        text,
        """        realcond->__data.__wrefs = 0;
        ret = pthread_cond_destroy(realcond);""",
        """        /* musl's destroy does not wait on an internal waiter count;
         * unlike glibc, no private-layout reset is needed or available. */
        ret = pthread_cond_destroy(realcond);""",
        path,
    )

    text = replace_once(
        text,
        """    return pthread_cond_clockwait(realcond, realmutex, clock_id, abstime);
}""",
        """    struct timespec realtime;
    int rc = _hybris_musl_clock_deadline(clock_id, abstime, &realtime);
    if (rc != 0)
        return rc;
    return pthread_cond_timedwait(realcond, realmutex, &realtime);
}""",
        path,
    )

    old = """    realattr = malloc(sizeof(pthread_rwlockattr_t));
    *((uintptr_t *)__attr) = (uintptr_t) realattr;

    return pthread_rwlockattr_init(realattr);"""
    new = """    struct hybris_musl_rwlockattr *wrapper = calloc(1, sizeof(*wrapper));
    if (!wrapper)
        return ENOMEM;
    wrapper->kind = HYBRIS_RWLOCK_PREFER_READER_NP;
    realattr = &wrapper->attr;
    *((uintptr_t *)__attr) = (uintptr_t) realattr;

    return pthread_rwlockattr_init(realattr);"""
    text = replace_once(text, old, new, path)

    text = replace_once(
        text,
        """    return pthread_rwlockattr_setkind_np(realattr, pref);
}""",
        """    struct hybris_musl_rwlockattr *wrapper =
        (struct hybris_musl_rwlockattr *)realattr;
    if (pref < HYBRIS_RWLOCK_PREFER_READER_NP ||
        pref > HYBRIS_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP)
        return EINVAL;
    /* musl exposes one rwlock policy. Retain the requested GNU metadata so
     * callers round-trip it, while the native lock keeps musl semantics. */
    wrapper->kind = pref;
    return 0;
}""",
        path,
    )
    text = replace_once(
        text,
        """    return pthread_rwlockattr_getkind_np(realattr, pref);
}""",
        """    struct hybris_musl_rwlockattr *wrapper =
        (struct hybris_musl_rwlockattr *)realattr;
    if (!pref)
        return EINVAL;
    *pref = wrapper->kind;
    return 0;
}""",
        path,
    )

    old = """    fpos_t my_fpos;
    int ret = fgetpos(_get_actual_fp(fp), &my_fpos);

    *pos = my_fpos.__pos;

    return ret;"""
    new = """    off_t offset = ftello(_get_actual_fp(fp));
    if (offset == (off_t)-1)
        return -1;
    *pos = (bionic_fpos_t)offset;
    return 0;"""
    text = replace_once(text, old, new, path)

    old = """    fpos64_t my_fpos;
    int ret = fgetpos64(_get_actual_fp(fp), &my_fpos);

    *pos = my_fpos.__pos;

    return ret;"""
    new = """    off_t offset = ftello(_get_actual_fp(fp));
    if (offset == (off_t)-1)
        return -1;
    *pos = (bionic_fpos64_t)offset;
    return 0;"""
    text = replace_once(text, old, new, path)

    text = replace_once(
        text,
        "return freopen64(filename, mode, _get_actual_fp(fp));",
        "return freopen(filename, mode, _get_actual_fp(fp));",
        path,
    )
    text = replace_once(
        text,
        "return fseeko64(_get_actual_fp(fp), offset, whence);",
        "return fseeko(_get_actual_fp(fp), (off_t)offset, whence);",
        path,
    )

    old = """    fpos_t my_fpos;
    my_fpos.__pos = *pos;
    memset(&my_fpos.__state, 0, sizeof(mbstate_t));

    return fsetpos(_get_actual_fp(fp), &my_fpos);"""
    new = """    return fseeko(_get_actual_fp(fp), (off_t)*pos, SEEK_SET);"""
    text = replace_once(text, old, new, path)

    old = """    fpos64_t my_fpos;
    my_fpos.__pos = *pos;
    memset(&my_fpos.__state, 0, sizeof(mbstate_t));

    return fsetpos64(_get_actual_fp(fp), &my_fpos);"""
    new = """    return fseeko(_get_actual_fp(fp), (off_t)*pos, SEEK_SET);"""
    text = replace_once(text, old, new, path)
    text = replace_once(
        text,
        "return ftello64(_get_actual_fp(fp));",
        "return (off64_t)ftello(_get_actual_fp(fp));",
        path,
    )

    old_start = text.index("static int _hybris_hook_scandirat(")
    old_end = text.index("\nstatic int _hybris_hook_scandir(", old_start)
    scandirat = r'''static int _hybris_hook_scandirat(int fd, const char *dir,
                      struct bionic_dirent ***namelist,
                      int (*filter) (const struct bionic_dirent *),
                      int (*compar) (const struct bionic_dirent **,
                                     const struct bionic_dirent **))
{
    struct bionic_dirent **result = NULL;
    size_t count = 0;
    size_t capacity = 0;
    int directory_fd;
    DIR *stream;
    int saved_errno = 0;

    if (!namelist) {
        errno = EINVAL;
        return -1;
    }
    *namelist = NULL;
    directory_fd = openat(fd, dir, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directory_fd < 0)
        return -1;
    stream = fdopendir(directory_fd);
    if (!stream) {
        saved_errno = errno;
        close(directory_fd);
        errno = saved_errno;
        return -1;
    }

    errno = 0;
    for (;;) {
        struct dirent *source = readdir(stream);
        struct bionic_dirent *entry;
        if (!source) {
            saved_errno = errno;
            break;
        }
        entry = calloc(1, sizeof(*entry));
        if (!entry) {
            saved_errno = ENOMEM;
            break;
        }
        entry->d_ino = source->d_ino;
        entry->d_off = source->d_off;
        entry->d_reclen = source->d_reclen;
        entry->d_type = source->d_type;
        strncpy(entry->d_name, source->d_name, sizeof(entry->d_name) - 1);
        if (filter && !filter(entry)) {
            free(entry);
            errno = 0;
            continue;
        }
        if (count == capacity) {
            size_t next_capacity = capacity ? capacity * 2 : 16;
            struct bionic_dirent **next;
            if (next_capacity > SIZE_MAX / sizeof(*result)) {
                free(entry);
                saved_errno = EOVERFLOW;
                break;
            }
            next = realloc(result, next_capacity * sizeof(*result));
            if (!next) {
                free(entry);
                saved_errno = ENOMEM;
                break;
            }
            result = next;
            capacity = next_capacity;
        }
        result[count++] = entry;
        errno = 0;
    }
    if (closedir(stream) != 0 && saved_errno == 0)
        saved_errno = errno;
    if (saved_errno != 0) {
        while (count > 0)
            free(result[--count]);
        free(result);
        errno = saved_errno;
        return -1;
    }
    if (count > INT_MAX) {
        while (count > 0)
            free(result[--count]);
        free(result);
        errno = EOVERFLOW;
        return -1;
    }
    if (count && compar)
        qsort(result, count, sizeof(*result),
              (int (*)(const void *, const void *))compar);
    *namelist = result;
    return (int)count;
}
'''
    text = text[:old_start] + scandirat + text[old_end:]

    text = replace_once(
        text,
        "return strerror_r(errnum, buf, buf_len);",
        """if (strerror_r(errnum, buf, buf_len) != 0 && buf_len > 0)
        snprintf(buf, buf_len, "Unknown error %d", errnum);
    return buf;""",
        path,
    )

    for old, new in (
        ("HOOK_DIRECT_NO_DEBUG(pvalloc)", "HOOK_TO(pvalloc, _hybris_musl_pvalloc)"),
        ("HOOK_DIRECT_NO_DEBUG(mallinfo)", "HOOK_TO(mallinfo, _hybris_musl_mallinfo)"),
        ("HOOK_DIRECT_NO_DEBUG(wmempcpy)", "HOOK_TO(wmempcpy, _hybris_musl_wmempcpy)"),
        ("HOOK_DIRECT_NO_DEBUG(fopen64)", "HOOK_TO(fopen64, fopen)"),
    ):
        text = replace_once(text, old, new, path)

    path.write_text(text)
    print(f"musl host hooks: patched {path}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} LIBHYBRIS_SOURCE")
    source = pathlib.Path(sys.argv[1]).resolve()
    common = source / "hybris" / "common"
    if not (common / "hooks.c").is_file():
        raise SystemExit(f"not a libhybris source tree: {source}")
    patch_linker_mutexes(common)
    patch_basename(common)
    patch_embedded_tls_lifecycle(common)
    patch_hooks(common)


if __name__ == "__main__":
    main()
