#include <assert.h>
#include <stdint.h>

#include "gralloc-pool-protocol.h"

int main(void)
{
    assert(sizeof(struct aurora_gralloc_pool_packet) == 192);
    assert(aurora_gralloc_pool_dimensions_valid(1920, 1080));
    assert(!aurora_gralloc_pool_dimensions_valid(0, 1080));
    assert(aurora_gralloc_pool_size_valid(3));
    assert(!aurora_gralloc_pool_size_valid(1));
    assert(!aurora_gralloc_pool_size_valid(7));

    struct aurora_gralloc_pool_packet packet =
        aurora_gralloc_pool_packet_init(AURORA_GRALLOC_POOL_BUFFER);
    packet.flags = AURORA_GRALLOC_POOL_FULL_HANDLE_RETAINED;
    packet.buffer_id = 1;
    packet.width = 1920;
    packet.height = 1080;
    packet.pool_size = 3;
    packet.handle_fd_count = 2;
    packet.native_int_count = 22;
    packet.plane_count = 1;
    packet.plane_fd_index[0] = 0;
    packet.pitch[0] = 1920 * 4;
    assert(aurora_gralloc_pool_buffer_valid(&packet));

    packet.plane_fd_index[0] = 2;
    assert(!aurora_gralloc_pool_buffer_valid(&packet));
    packet.plane_fd_index[0] = 0;
    packet.flags = 0;
    assert(!aurora_gralloc_pool_buffer_valid(&packet));
    return 0;
}
