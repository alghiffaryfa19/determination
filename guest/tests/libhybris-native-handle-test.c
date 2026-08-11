#define _GNU_SOURCE

/*
 * Display-less libhybris contract probe.
 *
 * EGL_PLATFORM=null initializes the vendor gralloc/EGL bridge without taking
 * the hwcomposer display from SurfaceFlinger.  The probe allocates one
 * Android buffer, inspects every native-handle payload entry, duplicates the
 * complete payload, and asks libhybris to reconstruct it.  It never presents,
 * changes a mode, or writes an installed file.
 */

#include <EGL/egl.h>

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define HYBRIS_USAGE_HW_TEXTURE 0x00000100
#define HYBRIS_USAGE_HW_RENDER 0x00000200
#define HYBRIS_USAGE_HW_COMPOSER 0x00000800
#define HYBRIS_PIXEL_FORMAT_RGBA_8888 1

typedef EGLBoolean(EGLAPIENTRYP create_native_buffer_fn)(
    EGLint width, EGLint height, EGLint usage, EGLint format,
    EGLint *stride, EGLClientBuffer *buffer);
typedef EGLBoolean(EGLAPIENTRYP release_native_buffer_fn)(EGLClientBuffer);
typedef void(EGLAPIENTRYP get_native_buffer_info_fn)(EGLClientBuffer,
                                                     int *, int *);
typedef void(EGLAPIENTRYP serialize_native_buffer_fn)(EGLClientBuffer,
                                                      int *, int *);
typedef EGLBoolean(EGLAPIENTRYP create_remote_buffer_fn)(
    EGLint width, EGLint height, EGLint usage, EGLint format, EGLint stride,
    int num_ints, int *ints, int num_fds, int *fds, EGLClientBuffer *buffer);

static void *get_proc(const char *name)
{
    void *proc = (void *)eglGetProcAddress(name);

    if (!proc)
        fprintf(stderr, "missing EGL procedure: %s (egl error 0x%x)\n",
                name, eglGetError());
    return proc;
}

static int fail_message(const char *message)
{
    fprintf(stderr, "native-handle contract: FAIL: %s\n", message);
    return 1;
}

int main(void)
{
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLClientBuffer original = NULL;
    EGLClientBuffer reconstructed = NULL;
    EGLint stride = 0;
    int num_ints = 0;
    int num_fds = 0;
    int *ints = NULL;
    int *fds = NULL;
    int *duplicates = NULL;
    int result = 1;

    create_native_buffer_fn create_buffer = NULL;
    release_native_buffer_fn release_buffer = NULL;
    get_native_buffer_info_fn get_info = NULL;
    serialize_native_buffer_fn serialize = NULL;
    create_remote_buffer_fn create_remote = NULL;
    void *swap_buffers_with_damage = NULL;

    if (strcmp(getenv("EGL_PLATFORM") ? getenv("EGL_PLATFORM") : "", "null") != 0 ||
        strcmp(getenv("HYBRIS_EGLPLATFORM") ? getenv("HYBRIS_EGLPLATFORM") : "", "null") != 0)
        return fail_message("probe must run with EGL_PLATFORM=null and HYBRIS_EGLPLATFORM=null");

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY)
        return fail_message("eglGetDisplay(null) returned EGL_NO_DISPLAY");
    if (!eglInitialize(display, NULL, NULL)) {
        fprintf(stderr, "native-handle contract: eglInitialize failed: 0x%x\n",
                eglGetError());
        goto out;
    }

    create_buffer = (create_native_buffer_fn)
        get_proc("eglHybrisCreateNativeBuffer");
    release_buffer = (release_native_buffer_fn)
        get_proc("eglHybrisReleaseNativeBuffer");
    get_info = (get_native_buffer_info_fn)
        get_proc("eglHybrisGetNativeBufferInfo");
    serialize = (serialize_native_buffer_fn)
        get_proc("eglHybrisSerializeNativeBuffer");
    create_remote = (create_remote_buffer_fn)
        get_proc("eglHybrisCreateRemoteBuffer");
    swap_buffers_with_damage = get_proc("eglSwapBuffersWithDamageKHR");
    if (!create_buffer || !release_buffer || !get_info || !serialize ||
        !create_remote || !swap_buffers_with_damage)
        goto out;

    if (!create_buffer(64, 64,
                       HYBRIS_USAGE_HW_TEXTURE | HYBRIS_USAGE_HW_RENDER |
                           HYBRIS_USAGE_HW_COMPOSER,
                       HYBRIS_PIXEL_FORMAT_RGBA_8888, &stride, &original) ||
        !original) {
        fprintf(stderr, "native-handle contract: gralloc allocation failed: 0x%x\n",
                eglGetError());
        goto out;
    }
    if (stride < 64)
        goto out_bad_shape;

    get_info(original, &num_ints, &num_fds);
    if (num_fds < 1 || num_fds > 64 || num_ints < 0 || num_ints > 4096) {
        fprintf(stderr,
                "native-handle contract: implausible payload fds=%d ints=%d\n",
                num_fds, num_ints);
        goto out;
    }
    ints = calloc((size_t)(num_ints ? num_ints : 1), sizeof(*ints));
    fds = calloc((size_t)num_fds, sizeof(*fds));
    duplicates = calloc((size_t)num_fds, sizeof(*duplicates));
    if (!ints || !fds || !duplicates)
        goto out_bad_alloc;

    serialize(original, ints, fds);
    for (int i = 0; i < num_fds; i++) {
        struct stat info;

        if (fds[i] < 0 || fstat(fds[i], &info) != 0) {
            fprintf(stderr,
                    "native-handle contract: serialized fd[%d] is invalid: %s\n",
                    i, strerror(errno));
            goto out;
        }
        duplicates[i] = fcntl(fds[i], F_DUPFD_CLOEXEC, 0);
        if (duplicates[i] < 0) {
            fprintf(stderr,
                    "native-handle contract: cannot duplicate fd[%d]: %s\n",
                    i, strerror(errno));
            goto out;
        }
    }

    /* libhybris consumes the duplicated fd array during mapper import. */
    if (!create_remote(64, 64,
                       HYBRIS_USAGE_HW_TEXTURE | HYBRIS_USAGE_HW_RENDER |
                           HYBRIS_USAGE_HW_COMPOSER,
                       HYBRIS_PIXEL_FORMAT_RGBA_8888, stride, num_ints, ints,
                       num_fds, duplicates, &reconstructed) ||
        !reconstructed)
        goto out_bad_reconstruct;

    printf("native-handle contract: PASS (%d fd%s, %d private int%s, stride=%d)\n",
           num_fds, num_fds == 1 ? "" : "s", num_ints,
           num_ints == 1 ? "" : "s", stride);
    result = 0;
    goto out;

out_bad_shape:
    fprintf(stderr, "native-handle contract: invalid stride=%d for 64px buffer\n",
            stride);
    goto out;
out_bad_alloc:
    fprintf(stderr, "native-handle contract: payload allocation failed\n");
    goto out;
out_bad_reconstruct:
    fprintf(stderr,
            "native-handle contract: complete native_handle reconstruction failed\n");
out:
    if (reconstructed && release_buffer)
        release_buffer(reconstructed);
    if (original && release_buffer)
        release_buffer(original);
    if (duplicates) {
        /* A failed import may consume some or all duplicates.  Do not close
         * them here: closing an already-consumed fd could risk closing an
         * unrelated descriptor if the vendor implementation reused a slot. */
        if (result != 0)
            memset(duplicates, 0, (size_t)num_fds * sizeof(*duplicates));
    }
    free(duplicates);
    free(fds);
    free(ints);
    if (display != EGL_NO_DISPLAY)
        eglTerminate(display);
    return result;
}
