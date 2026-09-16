#pragma once

#include <stdint.h>

#include "presenter-protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

struct aurora_presenter_client {
    int fd;
    void *nativewindow;
    void *create_from_handle;
    void *send_handle;
    void *release_buffer;
};

int aurora_presenter_connect(struct aurora_presenter_client *client,
                          const char *socket_path);
void aurora_presenter_disconnect(struct aurora_presenter_client *client);

int aurora_presenter_register_buffer(struct aurora_presenter_client *client,
                                  uint64_t buffer_id, uint32_t width,
                                  uint32_t height, uint32_t format,
                                  uint32_t stride, uint64_t usage,
                                  int num_ints, const int *ints,
                                  int num_fds, const int *fds);
int aurora_presenter_present(struct aurora_presenter_client *client,
                          uint64_t serial, uint64_t buffer_id,
                          uint64_t desired_present_time_ns,
                          int acquire_fence_fd);
int aurora_presenter_receive_completion(struct aurora_presenter_client *client,
                                     struct aurora_presenter_packet *packet,
                                     int *present_fence_fd,
                                     int *release_fence_fd);

#ifdef __cplusplus
}
#endif
