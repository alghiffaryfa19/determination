#include <libudev.h>
#include <stdio.h>
int main(void) {
    struct udev *u = udev_new();
    if (!u) return 1;
    struct udev_enumerate *e = udev_enumerate_new(u);
    if (!e) return 1;
    udev_enumerate_add_match_subsystem(e, "input");
    int rc = udev_enumerate_scan_devices(e), count = 0;
    struct udev_list_entry *entry;
    udev_list_entry_foreach(entry, udev_enumerate_get_list_entry(e)) {
        struct udev_device *d = udev_device_new_from_syspath(u, udev_list_entry_get_name(entry));
        if (!d) continue;
        const char *node = udev_device_get_devnode(d);
        if (node) { printf("node=%s\n", node); ++count; }
        udev_device_unref(d);
    }
    printf("scan_rc=%d nodes=%d\n", rc, count);
    udev_enumerate_unref(e);
    udev_unref(u);
    return rc < 0 || count == 0;
}
