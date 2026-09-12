#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "presenter-protocol.h"
#include "presenter-policy.h"
#include "presenter-session.h"

int main(void)
{
    struct aurora_presenter_packet packet =
        aurora_presenter_packet_init(AURORA_PRESENTER_PRESENT);

    assert(sizeof(packet) == 96);
    assert(packet.magic == AURORA_PRESENTER_MAGIC);
    assert(packet.version == AURORA_PRESENTER_VERSION);
    assert(packet.size == sizeof(packet));
    assert(packet.op == AURORA_PRESENTER_PRESENT);
    assert(packet.flags == 0);
    assert(packet.serial == 0);

    assert(aurora_presenter_dimensions_valid(1920, 1080));
    assert(!aurora_presenter_dimensions_valid(0, 1080));
    assert(!aurora_presenter_dimensions_valid(8193, 1080));
    assert(aurora_presenter_present_flags_valid(0));
    assert(aurora_presenter_present_flags_valid(AURORA_PRESENTER_HAS_ACQUIRE_FENCE));
    assert(!aurora_presenter_present_flags_valid(AURORA_PRESENTER_HAS_RELEASE_FENCE));
    assert(aurora_presenter_completion_flags_valid(
        AURORA_PRESENTER_HAS_PRESENT_FENCE | AURORA_PRESENTER_HAS_RELEASE_FENCE));
    assert(!aurora_presenter_completion_flags_valid(
        AURORA_PRESENTER_HAS_ACQUIRE_FENCE));

    struct aurora_presenter_session session;
    aurora_presenter_session_init(&session);
    assert(aurora_presenter_session_register(&session, 1, 1920, 1080) == 0);
    assert(aurora_presenter_session_register(&session, 1, 1920, 1080) == -1);
    for (uint64_t id = 2; id <= AURORA_PRESENTER_MAX_BUFFERS; ++id)
        assert(aurora_presenter_session_register(&session, id, 1, 1) == 0);
    assert(aurora_presenter_session_register(&session, 99, 1, 1) == -1);
    assert(aurora_presenter_session_present(&session, 7, 1) == 0);
    assert(aurora_presenter_session_present(&session, 7, 1) == -1);
    assert(aurora_presenter_session_unregister(&session, 1) == -1);
    assert(aurora_presenter_session_complete(&session, 8, 1, 0) == -1);
    assert(aurora_presenter_session_complete(&session, 7, 1, 2) == 0);
    assert(aurora_presenter_session_unregister(&session, 1) == 0);
    return 0;
}
