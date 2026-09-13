#define _GNU_SOURCE

/*
 * Android-gralloc pool broker for Mesa compositors.
 *
 * This process is the only guest process that loads libhybris/vendor EGL. It
 * allocates and retains complete Android native handles, registers them with
 * the Android presenter, advertises dma-buf plane candidates to KWin, and
 * forwards acquire/release sync_file fences. It never maps or copies pixels.
 */

#include <EGL/egl.h>
#include <drm_fourcc.h>
#include <gbm.h>
#include <hybris/common/binding.h>

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include "gralloc-pool-protocol.h"
#include "presenter-client.h"

#define DET_ANDROID_FORMAT_RGBA_8888 1u
#define DET_GRALLOC_USAGE_HW_TEXTURE UINT64_C(0x00000100)
#define DET_GRALLOC_USAGE_HW_RENDER UINT64_C(0x00000200)
#define DET_GRALLOC_USAGE_HW_COMPOSER UINT64_C(0x00000800)

typedef EGLBoolean(EGLAPIENTRYP det_create_native_buffer_fn)(
    EGLint, EGLint, EGLint, EGLint, EGLint *, EGLClientBuffer *);
typedef EGLBoolean(EGLAPIENTRYP det_release_native_buffer_fn)(EGLClientBuffer);
typedef void(EGLAPIENTRYP det_get_native_buffer_info_fn)(EGLClientBuffer,
                                                         int *, int *);
typedef void(EGLAPIENTRYP det_serialize_native_buffer_fn)(EGLClientBuffer,
                                                          int *, int *);

struct det_gralloc {
    EGLDisplay display;
    det_create_native_buffer_fn create;
    det_release_native_buffer_fn release;
    det_get_native_buffer_info_fn info;
    det_serialize_native_buffer_fn serialize;
};

struct det_pool_buffer {
    uint64_t id;
    EGLClientBuffer handle;
    int stride;
    uint32_t pitch;
    int num_ints;
    int num_fds;
    int *ints;
    int *fds;
    int payload_index;
    int minigbm_validated;
    uint64_t modifier;
};

static volatile sig_atomic_t running = 1;

static void stop_running(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static void *required_proc(const char *name)
{
    void *proc = (void *)eglGetProcAddress(name);
    if (!proc)
        fprintf(stderr, "det-gralloc-pool: missing %s\n", name);
    return proc;
}

static int gralloc_init(struct det_gralloc *gralloc)
{
    memset(gralloc, 0, sizeof(*gralloc));
    gralloc->display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (gralloc->display == EGL_NO_DISPLAY ||
        !eglInitialize(gralloc->display, NULL, NULL)) {
        fprintf(stderr, "det-gralloc-pool: EGL init failed 0x%x\n",
                eglGetError());
        return -1;
    }
    gralloc->create = (det_create_native_buffer_fn)
        required_proc("eglHybrisCreateNativeBuffer");
    gralloc->release = (det_release_native_buffer_fn)
        required_proc("eglHybrisReleaseNativeBuffer");
    gralloc->info = (det_get_native_buffer_info_fn)
        required_proc("eglHybrisGetNativeBufferInfo");
    gralloc->serialize = (det_serialize_native_buffer_fn)
        required_proc("eglHybrisSerializeNativeBuffer");
    return gralloc->create && gralloc->release && gralloc->info &&
                   gralloc->serialize
        ? 0 : -1;
}

static int choose_payload_fd(const int *fds, int count)
{
    off_t largest = -1;
    int selected = -1;

    for (int i = 0; i < count; ++i) {
        struct stat info;
        if (fstat(fds[i], &info) == 0) {
            fprintf(stderr,
                    "det-gralloc-pool: handle fd[%d] size=%lld\n",
                    i, (long long)info.st_size);
            if (info.st_size > largest) {
                largest = info.st_size;
                selected = i;
            }
        }
    }
    return selected;
}

static int validate_minigbm_node(const char *path, int dma_fd,
                                 uint32_t width, uint32_t height,
                                 uint32_t stride, uint64_t *modifier)
{
    struct gbm_import_fd_data data = {
        .fd = dma_fd,
        .width = width,
        .height = height,
        .stride = stride,
        .format = DRM_FORMAT_ABGR8888,
    };
    int node_fd = open(path, O_RDWR | O_CLOEXEC);
    if (node_fd < 0)
        return -1;
    struct gbm_device *device = gbm_create_device(node_fd);
    if (!device) {
        close(node_fd);
        return -1;
    }
    struct gbm_bo *bo = gbm_bo_import(device, GBM_BO_IMPORT_FD, &data,
                                      GBM_BO_USE_RENDERING);
    if (!bo) {
        gbm_device_destroy(device);
        close(node_fd);
        return -1;
    }
    *modifier = gbm_bo_get_modifier(bo);
    fprintf(stderr,
            "det-gralloc-pool: minigbm import PASS node=%s backend=%s "
            "stride=%u modifier=0x%llx\n",
            path, gbm_device_get_backend_name(device), gbm_bo_get_stride(bo),
            (unsigned long long)*modifier);
    gbm_bo_destroy(bo);
    gbm_device_destroy(device);
    close(node_fd);
    return 0;
}

static int validate_minigbm(const char *requested_node, int dma_fd,
                            uint32_t width, uint32_t height, uint32_t stride,
                            uint64_t *modifier)
{
    if (requested_node && strcmp(requested_node, "auto") != 0)
        return validate_minigbm_node(requested_node, dma_fd, width, height,
                                     stride, modifier);

    char path[64];
    for (unsigned int minor = 128; minor < 192; ++minor) {
        int length = snprintf(path, sizeof(path), "/dev/dri/renderD%u", minor);
        if (length > 0 && (size_t)length < sizeof(path) &&
            validate_minigbm_node(path, dma_fd, width, height, stride,
                                  modifier) == 0)
            return 0;
    }
    for (unsigned int card = 0; card < 16; ++card) {
        int length = snprintf(path, sizeof(path), "/dev/dri/card%u", card);
        if (length > 0 && (size_t)length < sizeof(path) &&
            validate_minigbm_node(path, dma_fd, width, height, stride,
                                  modifier) == 0)
            return 0;
    }
    return -1;
}

static int allocate_buffer(struct det_gralloc *gralloc,
                           struct det_presenter_client *presenter,
                           struct det_pool_buffer *buffer, uint64_t id,
                           uint32_t width, uint32_t height,
                           const char *gbm_node)
{
    const uint64_t usage = DET_GRALLOC_USAGE_HW_TEXTURE |
                           DET_GRALLOC_USAGE_HW_RENDER |
                           DET_GRALLOC_USAGE_HW_COMPOSER;
    memset(buffer, 0, sizeof(*buffer));
    buffer->id = id;
    buffer->payload_index = -1;
    buffer->modifier = DRM_FORMAT_MOD_INVALID;

    if (!gralloc->create((EGLint)width, (EGLint)height, (EGLint)usage,
                         DET_ANDROID_FORMAT_RGBA_8888, &buffer->stride,
                         &buffer->handle) || !buffer->handle)
        return -1;
    /*
     * libhybris reports Android RGBA_8888 stride in pixels. GBM and the
     * linux-dmabuf protocol use byte pitch. Advertising the pixel count as a
     * byte pitch makes Mesa advance only one quarter of a row, producing four
     * horizontally repeated images compressed into the top quarter.
     */
    if (buffer->stride <= 0 || (uint32_t)buffer->stride > UINT32_MAX / 4u) {
        errno = EOVERFLOW;
        return -1;
    }
    buffer->pitch = (uint32_t)buffer->stride * 4u;
    gralloc->info(buffer->handle, &buffer->num_ints, &buffer->num_fds);
    if (buffer->num_ints < 0 || buffer->num_ints > 128 ||
        buffer->num_fds <= 0 ||
        buffer->num_fds > (int)DET_GRALLOC_POOL_MAX_HANDLE_FDS) {
        errno = EOVERFLOW;
        return -1;
    }
    buffer->ints = calloc((size_t)buffer->num_ints, sizeof(*buffer->ints));
    buffer->fds = calloc((size_t)buffer->num_fds, sizeof(*buffer->fds));
    if ((!buffer->ints && buffer->num_ints) || !buffer->fds)
        return -1;
    gralloc->serialize(buffer->handle, buffer->ints, buffer->fds);

    buffer->payload_index = choose_payload_fd(buffer->fds, buffer->num_fds);
    if (buffer->payload_index < 0) {
        errno = ENODEV;
        return -1;
    }
    buffer->minigbm_validated =
        validate_minigbm(gbm_node, buffer->fds[buffer->payload_index],
                         width, height, buffer->pitch,
                         &buffer->modifier) == 0;
    if (!buffer->minigbm_validated) {
        buffer->modifier = DRM_FORMAT_MOD_INVALID;
        fprintf(stderr,
                "det-gralloc-pool: minigbm rejected buffer %llu; "
                "advertising it for a direct Mesa dma-buf import attempt\n",
                (unsigned long long)id);
    }
    if (det_presenter_register_buffer(
            presenter, id, width, height, DET_ANDROID_FORMAT_RGBA_8888,
            (uint32_t)buffer->stride, usage, buffer->num_ints, buffer->ints,
            buffer->num_fds, buffer->fds) != 0)
        return -1;

    fprintf(stderr,
            "det-gralloc-pool: buffer=%llu stride=%dpx pitch=%uB "
            "handle=%dfd+%dint "
            "payload-fd-index=%d retained=yes\n",
            (unsigned long long)id, buffer->stride, buffer->pitch,
            buffer->num_fds, buffer->num_ints, buffer->payload_index);
    return 0;
}

static void release_buffer(struct det_gralloc *gralloc,
                           struct det_pool_buffer *buffer)
{
    free(buffer->fds);
    free(buffer->ints);
    buffer->fds = NULL;
    buffer->ints = NULL;
    if (buffer->handle && gralloc->release)
        gralloc->release(buffer->handle);
    buffer->handle = NULL;
}

static int create_server(const char *path)
{
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (!path || strlen(path) >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    int fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return -1;
    memcpy(address.sun_path, path, strlen(path) + 1);
    unlink(path);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        chmod(path, 0666) != 0 || listen(fd, 1) != 0) {
        int saved = errno;
        close(fd);
        unlink(path);
        errno = saved;
        return -1;
    }
    return fd;
}

static int accept_compositor(int server, uid_t allowed_uid)
{
    int client = accept4(server, NULL, NULL, SOCK_CLOEXEC);
    if (client < 0)
        return -1;
    struct ucred credential;
    socklen_t size = sizeof(credential);
    if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &credential, &size) != 0 ||
        size != sizeof(credential) ||
        (credential.uid != allowed_uid && credential.uid != 0)) {
        fprintf(stderr,
                "det-gralloc-pool: rejected compositor peer uid=%u\n",
                size == sizeof(credential) ? credential.uid : UINT32_MAX);
        close(client);
        errno = EACCES;
        return -1;
    }
    fprintf(stderr, "det-gralloc-pool: compositor connected uid=%u pid=%d\n",
            credential.uid, credential.pid);
    return client;
}

static int send_buffer_packet(int fd, const struct det_pool_buffer *buffer,
                              uint32_t width, uint32_t height,
                              uint32_t pool_size)
{
    const uint64_t usage = DET_GRALLOC_USAGE_HW_TEXTURE |
                           DET_GRALLOC_USAGE_HW_RENDER |
                           DET_GRALLOC_USAGE_HW_COMPOSER;
    struct det_gralloc_pool_packet packet =
        det_gralloc_pool_packet_init(DET_GRALLOC_POOL_BUFFER);
    packet.flags = DET_GRALLOC_POOL_FULL_HANDLE_RETAINED;
    if (buffer->minigbm_validated)
        packet.flags |= DET_GRALLOC_POOL_MINIGBM_VALIDATED;
    packet.buffer_id = buffer->id;
    packet.width = width;
    packet.height = height;
    packet.android_format = DET_ANDROID_FORMAT_RGBA_8888;
    packet.drm_format = DRM_FORMAT_ABGR8888;
    packet.stride = (uint32_t)buffer->stride;
    packet.pool_size = pool_size;
    packet.handle_fd_count = (uint32_t)buffer->num_fds;
    packet.native_int_count = (uint32_t)buffer->num_ints;
    packet.plane_count = 1;
    packet.usage = usage;
    packet.modifier = buffer->modifier;
    packet.plane_fd_index[0] = (uint32_t)buffer->payload_index;
    packet.offset[0] = 0;
    packet.pitch[0] = buffer->pitch;

    struct iovec iov = {.iov_base = &packet, .iov_len = sizeof(packet)};
    char control[CMSG_SPACE(sizeof(int) * DET_GRALLOC_POOL_MAX_HANDLE_FDS)] = {0};
    struct msghdr message = {
        .msg_iov = &iov,
        .msg_iovlen = 1,
        .msg_control = control,
        .msg_controllen = CMSG_SPACE(sizeof(int) * (size_t)buffer->num_fds),
    };
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(sizeof(int) * (size_t)buffer->num_fds);
    memcpy(CMSG_DATA(header), buffer->fds,
           sizeof(int) * (size_t)buffer->num_fds);
    return sendmsg(fd, &message, MSG_NOSIGNAL) == (ssize_t)sizeof(packet)
        ? 0 : -1;
}

static int receive_present(int fd, struct det_gralloc_pool_packet *packet,
                           int *acquire_fence)
{
    struct iovec iov = {.iov_base = packet, .iov_len = sizeof(*packet)};
    char control[CMSG_SPACE(sizeof(int))] = {0};
    struct msghdr message = {
        .msg_iov = &iov,
        .msg_iovlen = 1,
        .msg_control = control,
        .msg_controllen = sizeof(control),
    };
    *acquire_fence = -1;
    ssize_t received = recvmsg(fd, &message, MSG_CMSG_CLOEXEC);
    if (received == 0) {
        errno = ECONNRESET;
        return -1;
    }
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    size_t fd_count = 0;
    if (header && header->cmsg_level == SOL_SOCKET &&
        header->cmsg_type == SCM_RIGHTS) {
        fd_count = (header->cmsg_len - CMSG_LEN(0)) / sizeof(int);
        if (fd_count == 1)
            memcpy(acquire_fence, CMSG_DATA(header), sizeof(int));
    }
    if (received != (ssize_t)sizeof(*packet) ||
        (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) ||
        packet->magic != DET_GRALLOC_POOL_MAGIC ||
        packet->version != DET_GRALLOC_POOL_VERSION ||
        packet->size != sizeof(*packet) ||
        packet->op != DET_GRALLOC_POOL_PRESENT ||
        packet->serial == 0 || packet->buffer_id == 0 ||
        fd_count > 1 ||
        (!!(packet->flags & DET_GRALLOC_POOL_HAS_ACQUIRE_FENCE) !=
         (fd_count == 1))) {
        if (*acquire_fence >= 0)
            close(*acquire_fence);
        *acquire_fence = -1;
        errno = EPROTO;
        return -1;
    }
    return 0;
}

static int send_completion(int fd,
                           const struct det_presenter_packet *completion,
                           int present_fence, int release_fence)
{
    struct det_gralloc_pool_packet packet =
        det_gralloc_pool_packet_init(DET_GRALLOC_POOL_COMPLETE);
    packet.serial = completion->serial;
    packet.buffer_id = completion->buffer_id;
    packet.released_buffer_id = completion->released_buffer_id;
    packet.latch_time_ns = completion->latch_time_ns;
    packet.callback_time_ns = completion->callback_time_ns;
    packet.status = completion->status;

    int fences[2];
    size_t fence_count = 0;
    if (present_fence >= 0) {
        packet.flags |= DET_GRALLOC_POOL_HAS_PRESENT_FENCE;
        fences[fence_count++] = present_fence;
    }
    if (release_fence >= 0) {
        packet.flags |= DET_GRALLOC_POOL_HAS_RELEASE_FENCE;
        fences[fence_count++] = release_fence;
    }
    struct iovec iov = {.iov_base = &packet, .iov_len = sizeof(packet)};
    char control[CMSG_SPACE(sizeof(fences))] = {0};
    struct msghdr message = {.msg_iov = &iov, .msg_iovlen = 1};
    if (fence_count) {
        message.msg_control = control;
        message.msg_controllen = CMSG_SPACE(sizeof(int) * fence_count);
        struct cmsghdr *header = CMSG_FIRSTHDR(&message);
        header->cmsg_level = SOL_SOCKET;
        header->cmsg_type = SCM_RIGHTS;
        header->cmsg_len = CMSG_LEN(sizeof(int) * fence_count);
        memcpy(CMSG_DATA(header), fences, sizeof(int) * fence_count);
    }
    return sendmsg(fd, &message, MSG_NOSIGNAL) == (ssize_t)sizeof(packet)
        ? 0 : -1;
}

static int buffer_id_valid(uint64_t id, uint32_t pool_size)
{
    return id > 0 && id <= pool_size;
}

int main(int argc, char **argv)
{
    if (argc < 5 || argc > 8) {
        fprintf(stderr,
                "usage: %s POOL_SOCKET PRESENTER_SOCKET WIDTH HEIGHT "
                "[POOL_SIZE] [GBM_NODE|auto] [ALLOWED_UID]\n", argv[0]);
        return 2;
    }
    const char *pool_socket = argv[1];
    const char *presenter_socket = argv[2];
    uint32_t width = (uint32_t)strtoul(argv[3], NULL, 10);
    uint32_t height = (uint32_t)strtoul(argv[4], NULL, 10);
    uint32_t pool_size = argc > 5 ? (uint32_t)strtoul(argv[5], NULL, 10) : 3;
    const char *gbm_node = argc > 6 ? argv[6] : "auto";
    uid_t allowed_uid = argc > 7 ? (uid_t)strtoul(argv[7], NULL, 10) : 1000;
    if (!det_gralloc_pool_dimensions_valid(width, height) ||
        !det_gralloc_pool_size_valid(pool_size)) {
        fprintf(stderr, "det-gralloc-pool: invalid geometry or pool size\n");
        return 2;
    }

    signal(SIGINT, stop_running);
    signal(SIGTERM, stop_running);
    struct det_gralloc gralloc;
    struct det_presenter_client presenter = {.fd = -1};
    struct det_pool_buffer buffers[DET_GRALLOC_POOL_MAX_BUFFERS] = {0};
    int server = -1;
    int compositor = -1;
    int result = 1;

    if (gralloc_init(&gralloc) != 0 ||
        det_presenter_connect(&presenter, presenter_socket) != 0) {
        fprintf(stderr, "det-gralloc-pool: presenter setup failed: %s\n",
                strerror(errno));
        goto out;
    }
    for (uint32_t i = 0; i < pool_size; ++i) {
        if (allocate_buffer(&gralloc, &presenter, &buffers[i], i + 1,
                            width, height, gbm_node) != 0) {
            fprintf(stderr,
                    "det-gralloc-pool: buffer %u allocation/register failed: "
                    "%s\n", i + 1, strerror(errno));
            goto out;
        }
    }
    server = create_server(pool_socket);
    if (server < 0) {
        fprintf(stderr, "det-gralloc-pool: listen %s failed: %s\n",
                pool_socket, strerror(errno));
        goto out;
    }
    fprintf(stderr,
            "det-gralloc-pool: ready socket=%s geometry=%ux%u pool=%u "
            "renderer-contract=dma-buf+sync_file\n",
            pool_socket, width, height, pool_size);
    compositor = accept_compositor(server, allowed_uid);
    if (compositor < 0)
        goto out;
    for (uint32_t i = 0; i < pool_size; ++i) {
        if (send_buffer_packet(compositor, &buffers[i], width, height,
                               pool_size) != 0)
            goto out;
    }

    while (running) {
        struct det_gralloc_pool_packet request;
        struct det_presenter_packet completion;
        int acquire_fence = -1;
        int present_fence = -1;
        int release_fence = -1;
        if (receive_present(compositor, &request, &acquire_fence) != 0)
            break;
        if (!buffer_id_valid(request.buffer_id, pool_size) ||
            det_presenter_present(&presenter, request.serial,
                                  request.buffer_id,
                                  request.desired_present_time_ns,
                                  acquire_fence) != 0) {
            if (acquire_fence >= 0)
                close(acquire_fence);
            break;
        }
        if (acquire_fence >= 0)
            close(acquire_fence);
        struct pollfd ready = {.fd = presenter.fd, .events = POLLIN};
        if (poll(&ready, 1, 5000) <= 0 ||
            det_presenter_receive_completion(&presenter, &completion,
                                              &present_fence,
                                              &release_fence) != 0 ||
            completion.serial != request.serial ||
            !buffer_id_valid(completion.buffer_id, pool_size) ||
            (completion.released_buffer_id != 0 &&
             !buffer_id_valid(completion.released_buffer_id, pool_size)) ||
            send_completion(compositor, &completion, present_fence,
                            release_fence) != 0) {
            if (present_fence >= 0)
                close(present_fence);
            if (release_fence >= 0)
                close(release_fence);
            break;
        }
        if (present_fence >= 0)
            close(present_fence);
        if (release_fence >= 0)
            close(release_fence);
    }
    if (!running || errno == ECONNRESET)
        result = 0;

out:
    if (compositor >= 0)
        close(compositor);
    if (server >= 0)
        close(server);
    unlink(pool_socket);
    det_presenter_disconnect(&presenter);
    for (uint32_t i = 0; i < pool_size; ++i)
        release_buffer(&gralloc, &buffers[i]);
    if (gralloc.display && gralloc.display != EGL_NO_DISPLAY)
        eglTerminate(gralloc.display);
    return result;
}
