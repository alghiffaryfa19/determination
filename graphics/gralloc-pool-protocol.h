#pragma once

/*
 * Android-gralloc pool <-> Mesa compositor protocol.
 *
 * The libhybris helper owns every complete Android native_handle and the
 * Android presenter connection. BUFFER carries duplicated handle fds over
 * AF_UNIX SOCK_SEQPACKET; plane_fd_index selects the dma-buf planes that Mesa
 * may import. Native-handle private integers never enter the Mesa process.
 * PRESENT carries one acquire sync_file. COMPLETE optionally carries present
 * and previous-buffer release sync_files, in that order.
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DET_GRALLOC_POOL_MAGIC UINT32_C(0x44475031) /* "DGP1" */
#define DET_GRALLOC_POOL_VERSION 1u
#define DET_GRALLOC_POOL_MAX_BUFFERS 6u
#define DET_GRALLOC_POOL_MAX_HANDLE_FDS 16u
#define DET_GRALLOC_POOL_MAX_PLANES 4u

enum det_gralloc_pool_op {
    DET_GRALLOC_POOL_BUFFER = 1,
    DET_GRALLOC_POOL_PRESENT = 2,
};

#define DET_GRALLOC_POOL_COMPLETE UINT32_C(0x80000002)
#define DET_GRALLOC_POOL_ERROR UINT32_C(0x800000ff)

enum det_gralloc_pool_flags {
    DET_GRALLOC_POOL_FULL_HANDLE_RETAINED = 1u << 0,
    DET_GRALLOC_POOL_MINIGBM_VALIDATED = 1u << 1,
    DET_GRALLOC_POOL_HAS_ACQUIRE_FENCE = 1u << 2,
    DET_GRALLOC_POOL_HAS_PRESENT_FENCE = 1u << 3,
    DET_GRALLOC_POOL_HAS_RELEASE_FENCE = 1u << 4,
};

struct det_gralloc_pool_packet {
    uint32_t magic;
    uint16_t version;
    uint16_t size;
    uint32_t op;
    uint32_t flags;
    uint64_t serial;
    uint64_t buffer_id;
    uint64_t released_buffer_id;
    uint64_t desired_present_time_ns;
    int64_t latch_time_ns;
    int64_t callback_time_ns;
    uint32_t width;
    uint32_t height;
    uint32_t android_format;
    uint32_t drm_format;
    uint32_t stride;
    uint32_t pool_size;
    uint32_t handle_fd_count;
    uint32_t plane_count;
    uint64_t usage;
    uint64_t modifier;
    int32_t status;
    uint32_t native_int_count;
    uint32_t plane_fd_index[DET_GRALLOC_POOL_MAX_PLANES];
    uint32_t offset[DET_GRALLOC_POOL_MAX_PLANES];
    uint32_t pitch[DET_GRALLOC_POOL_MAX_PLANES];
    uint64_t reserved[3];
};

#ifdef __cplusplus
static_assert(sizeof(det_gralloc_pool_packet) == 192,
              "gralloc pool protocol layout changed");
#else
_Static_assert(sizeof(struct det_gralloc_pool_packet) == 192,
               "gralloc pool protocol layout changed");
#endif

static inline struct det_gralloc_pool_packet
det_gralloc_pool_packet_init(uint32_t op)
{
#ifdef __cplusplus
    struct det_gralloc_pool_packet packet{};
#else
    struct det_gralloc_pool_packet packet = {0};
#endif
    packet.magic = DET_GRALLOC_POOL_MAGIC;
    packet.version = DET_GRALLOC_POOL_VERSION;
    packet.size = (uint16_t)sizeof(packet);
    packet.op = op;
    return packet;
}

static inline int det_gralloc_pool_dimensions_valid(uint32_t width,
                                                    uint32_t height)
{
    return width > 0 && width <= 8192 && height > 0 && height <= 8192;
}

static inline int det_gralloc_pool_size_valid(uint32_t size)
{
    return size >= 2 && size <= DET_GRALLOC_POOL_MAX_BUFFERS;
}

static inline int det_gralloc_pool_buffer_valid(
    const struct det_gralloc_pool_packet *packet)
{
    if (!packet ||
        packet->magic != DET_GRALLOC_POOL_MAGIC ||
        packet->version != DET_GRALLOC_POOL_VERSION ||
        packet->size != sizeof(*packet) ||
        packet->op != DET_GRALLOC_POOL_BUFFER ||
        !det_gralloc_pool_dimensions_valid(packet->width, packet->height) ||
        !det_gralloc_pool_size_valid(packet->pool_size) ||
        packet->buffer_id == 0 ||
        packet->handle_fd_count == 0 ||
        packet->handle_fd_count > DET_GRALLOC_POOL_MAX_HANDLE_FDS ||
        packet->plane_count == 0 ||
        packet->plane_count > DET_GRALLOC_POOL_MAX_PLANES ||
        !(packet->flags & DET_GRALLOC_POOL_FULL_HANDLE_RETAINED))
        return 0;
    for (uint32_t i = 0; i < packet->plane_count; ++i) {
        if (packet->plane_fd_index[i] >= packet->handle_fd_count ||
            packet->pitch[i] == 0)
            return 0;
    }
    return 1;
}

#ifdef __cplusplus
}
#endif
