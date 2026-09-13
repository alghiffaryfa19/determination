#pragma once

#include <stdint.h>

#define DET_INPUT_FORWARD_MAGIC UINT32_C(0x44494631) /* "DIF1" */
#define DET_INPUT_FORWARD_VERSION 1u
#define DET_INPUT_MAX_SOURCES 64u
#define DET_INPUT_ANDROID_TOUCH_SOURCE_ID DET_INPUT_MAX_SOURCES

enum det_input_source_flags {
    DET_INPUT_SOURCE_ABSOLUTE = 1u << 0,
    DET_INPUT_SOURCE_DIRECT = 1u << 1,
    DET_INPUT_SOURCE_MULTITOUCH = 1u << 2,
};

struct det_input_forward_packet {
    uint32_t magic;
    uint16_t version;
    uint16_t size;
    uint32_t source_id;
    uint16_t type;
    uint16_t code;
    int32_t value;
    int32_t minimum;
    int32_t maximum;
    uint32_t source_flags;
    uint32_t reserved[4];
};

#ifdef __cplusplus
static_assert(sizeof(det_input_forward_packet) == 48,
              "input forward protocol layout changed");
#else
_Static_assert(sizeof(struct det_input_forward_packet) == 48,
               "input forward protocol layout changed");
#endif
