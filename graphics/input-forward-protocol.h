#pragma once

#include <stdint.h>

#define AURORA_INPUT_FORWARD_MAGIC UINT32_C(0x44494631) /* "DIF1" */
#define AURORA_INPUT_FORWARD_VERSION 1u
#define AURORA_INPUT_MAX_SOURCES 64u
#define AURORA_INPUT_ANDROID_TOUCH_SOURCE_ID AURORA_INPUT_MAX_SOURCES

enum aurora_input_source_flags {
    AURORA_INPUT_SOURCE_ABSOLUTE = 1u << 0,
    AURORA_INPUT_SOURCE_DIRECT = 1u << 1,
    AURORA_INPUT_SOURCE_MULTITOUCH = 1u << 2,
};

struct aurora_input_forward_packet {
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
static_assert(sizeof(aurora_input_forward_packet) == 48,
              "input forward protocol layout changed");
#else
_Static_assert(sizeof(struct aurora_input_forward_packet) == 48,
               "input forward protocol layout changed");
#endif
