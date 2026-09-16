#include <libinput.h>
#include <libudev.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
static int open_device(const char *path, int flags, void *data) {
    (void)data;
    int fd = open(path, flags);
    return fd < 0 ? -errno : fd;
}
static void close_device(int fd, void *data) { (void)data; close(fd); }
int main(void) {
    const struct libinput_interface ops = {open_device, close_device};
    struct udev *udev = udev_new();
    if (!udev) return 1;
    struct libinput *li = libinput_udev_create_context(&ops, NULL, udev);
    if (!li) return 1;
    if (libinput_udev_assign_seat(li, "seat0") != 0) return 1;
    libinput_dispatch(li);
    struct libinput_event *event;
    int count = 0, touch = 0;
    while ((event = libinput_get_event(li))) {
        if (libinput_event_get_type(event) == LIBINPUT_EVENT_DEVICE_ADDED) {
            struct libinput_device *d = libinput_event_get_device(event);
            int t = libinput_device_has_capability(d, LIBINPUT_DEVICE_CAP_TOUCH);
            printf("device=%s touch=%d keyboard=%d pointer=%d\n", libinput_device_get_name(d), t,
                libinput_device_has_capability(d, LIBINPUT_DEVICE_CAP_KEYBOARD),
                libinput_device_has_capability(d, LIBINPUT_DEVICE_CAP_POINTER));
            ++count; touch += t;
        }
        libinput_event_destroy(event);
    }
    printf("devices=%d touchscreens=%d\n", count, touch);
    libinput_unref(li);
    udev_unref(udev);
    return count == 0 || touch == 0;
}
