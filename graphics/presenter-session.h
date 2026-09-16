#pragma once

#include <stddef.h>
#include <stdint.h>

#include "presenter-policy.h"

struct aurora_presenter_session {
    uint64_t buffers[AURORA_PRESENTER_MAX_BUFFERS];
    uint64_t buffer_pixels[AURORA_PRESENTER_MAX_BUFFERS];
    uint64_t serials[AURORA_PRESENTER_MAX_INFLIGHT_FRAMES];
    uint64_t inflight_buffers[AURORA_PRESENTER_MAX_INFLIGHT_FRAMES];
    uint64_t registered_pixels;
    size_t buffer_count;
    size_t inflight_count;
};

void aurora_presenter_session_init(struct aurora_presenter_session *session);
int aurora_presenter_session_register(struct aurora_presenter_session *session,
                                   uint64_t buffer_id, uint32_t width,
                                   uint32_t height);
int aurora_presenter_session_unregister(struct aurora_presenter_session *session,
                                     uint64_t buffer_id);
int aurora_presenter_session_present(struct aurora_presenter_session *session,
                                  uint64_t serial, uint64_t buffer_id);
int aurora_presenter_session_complete(struct aurora_presenter_session *session,
                                   uint64_t serial, uint64_t buffer_id,
                                   uint64_t released_buffer_id);
