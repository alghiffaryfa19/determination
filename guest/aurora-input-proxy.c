#define _GNU_SOURCE

/*
 * Guest-side evdev -> compositor input proxy.
 *
 * Raw events arrive from the root Android capture helper. This process uses
 * KWin uses its native fake-input protocol. Phoc uses wlroots virtual pointer
 * and virtual keyboard. Both avoid uinput devices that Android InputReader
 * could rediscover and consume.
 */

#include <errno.h>
#include <fcntl.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "fake-input-client-protocol.h"
#include "input-forward-protocol.h"
#include "virtual-keyboard-client-protocol.h"
#include "wlr-virtual-pointer-client-protocol.h"

#define AURORA_MAX_TOUCH_SLOTS 32

struct aurora_touch_slot {
    int tracking_id;
    int x;
    int y;
    int minimum_x;
    int maximum_x;
    int minimum_y;
    int maximum_y;
    int have_x;
    int have_y;
    int active;
    int pending_down;
    int pending_up;
    int dirty;
};

struct aurora_source_state {
    uint32_t flags;
    double relative_x;
    double relative_y;
    int absolute_x;
    int absolute_y;
    int minimum_x;
    int maximum_x;
    int minimum_y;
    int maximum_y;
    int absolute_dirty;
    int wheel_vertical;
    int wheel_horizontal;
    int wheel_vertical_hi_res;
    int wheel_horizontal_hi_res;
    int current_slot;
    int single_touch_active;
    int single_touch_pending_down;
    int single_touch_pending_up;
    struct aurora_touch_slot slots[AURORA_MAX_TOUCH_SLOTS];
};

static volatile sig_atomic_t running = 1;
static struct org_kde_kwin_fake_input *fake_input;
static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *pointer_manager;
static struct zwlr_virtual_pointer_v1 *virtual_pointer;
static struct zwp_virtual_keyboard_manager_v1 *keyboard_manager;
static struct zwp_virtual_keyboard_v1 *virtual_keyboard;

static uint32_t event_time_ms(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)((uint64_t)now.tv_sec * 1000u +
                      (uint64_t)now.tv_nsec / 1000000u);
}

static void stop_running(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version)
{
    (void)data;
    if (strcmp(interface, org_kde_kwin_fake_input_interface.name) == 0) {
        uint32_t bind_version = version < 5 ? version : 5;
        fake_input = wl_registry_bind(
            registry, name, &org_kde_kwin_fake_input_interface, bind_version);
    } else if (strcmp(interface, wl_seat_interface.name) == 0 && !seat) {
        uint32_t bind_version = version < 7 ? version : 7;
        seat = wl_registry_bind(registry, name, &wl_seat_interface,
                                bind_version);
    } else if (strcmp(interface,
                      zwlr_virtual_pointer_manager_v1_interface.name) == 0) {
        uint32_t bind_version = version < 2 ? version : 2;
        pointer_manager = wl_registry_bind(
            registry, name, &zwlr_virtual_pointer_manager_v1_interface,
            bind_version);
    } else if (strcmp(interface,
                      zwp_virtual_keyboard_manager_v1_interface.name) == 0) {
        keyboard_manager = wl_registry_bind(
            registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    }
}

static void registry_remove(void *data, struct wl_registry *registry,
                            uint32_t name)
{
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_remove,
};

static struct wl_display *connect_wayland(void)
{
    for (int attempt = 0; attempt < 100 && running; ++attempt) {
        struct wl_display *display = wl_display_connect(NULL);
        if (display)
            return display;
        usleep(100000);
    }
    return NULL;
}

static int send_default_keymap(void)
{
    static const char keymap[] =
        "xkb_keymap {\n"
        " xkb_keycodes { include \"evdev+aliases(qwerty)\" };\n"
        " xkb_types { include \"complete\" };\n"
        " xkb_compatibility { include \"complete\" };\n"
        " xkb_symbols { include \"pc+us+inet(evdev)\" };\n"
        " xkb_geometry { include \"pc(pc105)\" };\n"
        "};\n";
    int fd = memfd_create("aurora-keymap", MFD_CLOEXEC);
    if (fd < 0)
        return -1;
    size_t offset = 0;
    while (offset < sizeof(keymap)) {
        ssize_t written = write(fd, keymap + offset, sizeof(keymap) - offset);
        if (written <= 0) {
            int saved = errno;
            close(fd);
            errno = saved;
            return -1;
        }
        offset += (size_t)written;
    }
    zwp_virtual_keyboard_v1_keymap(
        virtual_keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd,
        (uint32_t)sizeof(keymap));
    close(fd);
    return 0;
}

static int initialize_input_protocols(void)
{
    if (fake_input) {
        org_kde_kwin_fake_input_authenticate(
            fake_input, "Aurora", "User enabled peripheral capture");
        fprintf(stderr, "aurora-input-proxy: using KDE fake-input\n");
        return 0;
    }
    if (!seat || (!pointer_manager && !keyboard_manager)) {
        errno = ENOTSUP;
        return -1;
    }
    if (pointer_manager) {
        virtual_pointer =
            zwlr_virtual_pointer_manager_v1_create_virtual_pointer(
                pointer_manager, seat);
    }
    if (keyboard_manager) {
        virtual_keyboard =
            zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(
                keyboard_manager, seat);
        if (!virtual_keyboard || send_default_keymap() != 0)
            return -1;
    }
    fprintf(stderr,
            "aurora-input-proxy: using wlroots virtual keyboard/pointer\n");
    return 0;
}

static void destroy_input_protocols(void)
{
    if (fake_input)
        org_kde_kwin_fake_input_destroy(fake_input);
    if (virtual_keyboard)
        zwp_virtual_keyboard_v1_destroy(virtual_keyboard);
    if (virtual_pointer)
        zwlr_virtual_pointer_v1_destroy(virtual_pointer);
    if (keyboard_manager)
        zwp_virtual_keyboard_manager_v1_destroy(keyboard_manager);
    if (pointer_manager)
        zwlr_virtual_pointer_manager_v1_destroy(pointer_manager);
    if (seat)
        wl_seat_destroy(seat);
}

static int create_pipe(const char *path)
{
    if (!path || !*path) {
        errno = EINVAL;
        return -1;
    }
    struct stat info;
    int stat_result = lstat(path, &info);
    if (stat_result != 0 && errno != ENOENT)
        return -1;
    if (stat_result != 0 || !S_ISFIFO(info.st_mode)) {
        if (stat_result == 0 && unlink(path) != 0)
            return -1;
        if (mkfifo(path, 0600) != 0)
            return -1;
    }
    /* O_RDWR keeps the reader alive while no capture helper is attached.
     * FIFOs cross the Android/LXC namespace boundary through the shared
     * control mount; AF_UNIX pathname sockets do not on this kernel. */
    int fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        int saved = errno;
        errno = saved;
        return -1;
    }
    return fd;
}

static int connect_touch_socket(const char *path)
{
    if (!path || !*path || strcmp(path, "-") == 0) {
        errno = ENOENT;
        return -1;
    }
    if (strlen(path) >= sizeof(((struct sockaddr_un *)0)->sun_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    int fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return -1;
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    memcpy(address.sun_path, path, strlen(path) + 1);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int saved = errno;
        close(fd);
        errno = saved;
        return -1;
    }
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
        int saved = errno;
        close(fd);
        errno = saved;
        return -1;
    }
    fprintf(stderr, "aurora-input-proxy: Android display touch connected %s\n",
            path);
    return fd;
}

static void send_scroll_axis(uint32_t axis, int legacy, int hi_res)
{
    if (legacy == 0 && hi_res == 0)
        return;

    /* Linux high-resolution wheel units use 120 units per detent. Devices
     * generally send a matching REL_WHEEL event as compatibility output, so
     * never add both or scrolling becomes coarse and visibly jittery. */
    double steps = hi_res != 0 ? (double)hi_res / 120.0 : (double)legacy;
    double distance = -15.0 * steps;
    int discrete = hi_res != 0 ? hi_res / 120 : legacy;
    if (fake_input)
        org_kde_kwin_fake_input_axis(
            fake_input, axis, wl_fixed_from_double(distance));
    if (virtual_pointer) {
        zwlr_virtual_pointer_v1_axis_source(
            virtual_pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
        zwlr_virtual_pointer_v1_axis_discrete(
            virtual_pointer, event_time_ms(), axis,
            wl_fixed_from_double(distance), -discrete);
    }
}

static double normalize(int value, int minimum, int maximum, int extent)
{
    if (maximum <= minimum || extent <= 0)
        return 0.0;
    double normalized =
        (double)(value - minimum) / (double)(maximum - minimum);
    if (normalized < 0.0)
        normalized = 0.0;
    if (normalized > 1.0)
        normalized = 1.0;
    return normalized * (double)(extent - 1);
}

static uint32_t touch_id(uint32_t source_id, uint32_t slot)
{
    return (source_id - 1u) * AURORA_MAX_TOUCH_SLOTS + slot;
}

static int flush_direct_touch(struct aurora_source_state *source,
                              uint32_t source_id, int width, int height)
{
    if (!fake_input || !(source->flags & AURORA_INPUT_SOURCE_DIRECT))
        return 0;

    int emitted = 0;
    if (source->flags & AURORA_INPUT_SOURCE_MULTITOUCH) {
        for (uint32_t index = 0; index < AURORA_MAX_TOUCH_SLOTS; ++index) {
            struct aurora_touch_slot *slot = &source->slots[index];
            const uint32_t id = touch_id(source_id, index);
            if (slot->pending_up) {
                if (slot->active) {
                    org_kde_kwin_fake_input_touch_up(fake_input, id);
                    emitted = 1;
                }
                slot->active = 0;
                slot->pending_up = 0;
                slot->pending_down = 0;
                slot->dirty = 0;
            }
            if (slot->pending_down && slot->tracking_id >= 0 &&
                slot->have_x && slot->have_y) {
                double x = normalize(slot->x, slot->minimum_x,
                                     slot->maximum_x, width);
                double y = normalize(slot->y, slot->minimum_y,
                                     slot->maximum_y, height);
                org_kde_kwin_fake_input_touch_down(
                    fake_input, id, wl_fixed_from_double(x),
                    wl_fixed_from_double(y));
                slot->active = 1;
                slot->pending_down = 0;
                slot->dirty = 0;
                emitted = 1;
            } else if (slot->active && slot->dirty &&
                       slot->have_x && slot->have_y) {
                double x = normalize(slot->x, slot->minimum_x,
                                     slot->maximum_x, width);
                double y = normalize(slot->y, slot->minimum_y,
                                     slot->maximum_y, height);
                org_kde_kwin_fake_input_touch_motion(
                    fake_input, id, wl_fixed_from_double(x),
                    wl_fixed_from_double(y));
                slot->dirty = 0;
                emitted = 1;
            }
        }
    } else {
        const uint32_t id = touch_id(source_id, 0);
        if (source->single_touch_pending_up) {
            if (source->single_touch_active) {
                org_kde_kwin_fake_input_touch_up(fake_input, id);
                emitted = 1;
            }
            source->single_touch_active = 0;
            source->single_touch_pending_up = 0;
        }
        if (source->single_touch_pending_down && source->absolute_dirty) {
            double x = normalize(source->absolute_x, source->minimum_x,
                                 source->maximum_x, width);
            double y = normalize(source->absolute_y, source->minimum_y,
                                 source->maximum_y, height);
            org_kde_kwin_fake_input_touch_down(
                fake_input, id, wl_fixed_from_double(x),
                wl_fixed_from_double(y));
            source->single_touch_active = 1;
            source->single_touch_pending_down = 0;
            source->absolute_dirty = 0;
            emitted = 1;
        } else if (source->single_touch_active && source->absolute_dirty) {
            double x = normalize(source->absolute_x, source->minimum_x,
                                 source->maximum_x, width);
            double y = normalize(source->absolute_y, source->minimum_y,
                                 source->maximum_y, height);
            org_kde_kwin_fake_input_touch_motion(
                fake_input, id, wl_fixed_from_double(x),
                wl_fixed_from_double(y));
            source->absolute_dirty = 0;
            emitted = 1;
        }
    }
    if (emitted)
        org_kde_kwin_fake_input_touch_frame(fake_input);
    return 1;
}

static void cancel_direct_touch(struct aurora_source_state *source)
{
    if (fake_input && (source->flags & AURORA_INPUT_SOURCE_DIRECT))
        org_kde_kwin_fake_input_touch_cancel(fake_input);
    source->single_touch_active = 0;
    source->single_touch_pending_down = 0;
    source->single_touch_pending_up = 0;
    for (uint32_t index = 0; index < AURORA_MAX_TOUCH_SLOTS; ++index) {
        source->slots[index].tracking_id = -1;
        source->slots[index].active = 0;
        source->slots[index].pending_down = 0;
        source->slots[index].pending_up = 0;
        source->slots[index].dirty = 0;
    }
}

static void flush_source(struct aurora_source_state *source,
                         uint32_t source_id, int width, int height)
{
    uint32_t time = event_time_ms();
    if (source->relative_x != 0.0 || source->relative_y != 0.0) {
        if (fake_input)
            org_kde_kwin_fake_input_pointer_motion(
                fake_input, wl_fixed_from_double(source->relative_x),
                wl_fixed_from_double(source->relative_y));
        if (virtual_pointer)
            zwlr_virtual_pointer_v1_motion(
                virtual_pointer, time,
                wl_fixed_from_double(source->relative_x),
                wl_fixed_from_double(source->relative_y));
        source->relative_x = 0.0;
        source->relative_y = 0.0;
    }
    const int direct_touch =
        flush_direct_touch(source, source_id, width, height);
    if (source->absolute_dirty && !direct_touch) {
        double x = normalize(source->absolute_x, source->minimum_x,
                             source->maximum_x, width);
        double y = normalize(source->absolute_y, source->minimum_y,
                             source->maximum_y, height);
        if (fake_input)
            org_kde_kwin_fake_input_pointer_motion_absolute(
                fake_input, wl_fixed_from_double(x), wl_fixed_from_double(y));
        if (virtual_pointer)
            zwlr_virtual_pointer_v1_motion_absolute(
                virtual_pointer, time, (uint32_t)x, (uint32_t)y,
                (uint32_t)width, (uint32_t)height);
        source->absolute_dirty = 0;
    }
    send_scroll_axis(WL_POINTER_AXIS_VERTICAL_SCROLL,
                     source->wheel_vertical,
                     source->wheel_vertical_hi_res);
    send_scroll_axis(WL_POINTER_AXIS_HORIZONTAL_SCROLL,
                     source->wheel_horizontal,
                     source->wheel_horizontal_hi_res);
    source->wheel_vertical = 0;
    source->wheel_horizontal = 0;
    source->wheel_vertical_hi_res = 0;
    source->wheel_horizontal_hi_res = 0;
    if (virtual_pointer)
        zwlr_virtual_pointer_v1_frame(virtual_pointer);
}

static int dispatch_packet(const struct aurora_input_forward_packet *packet,
                           struct aurora_source_state *sources,
                           int width, int height)
{
    if (packet->magic != AURORA_INPUT_FORWARD_MAGIC ||
        packet->version != AURORA_INPUT_FORWARD_VERSION ||
        packet->size != sizeof(*packet) ||
        packet->source_id == 0 ||
        packet->source_id > AURORA_INPUT_MAX_SOURCES ||
        packet->type > EV_MAX) {
        errno = EPROTO;
        return -1;
    }
    struct aurora_source_state *source = &sources[packet->source_id - 1];
    source->flags = packet->source_flags;
    switch (packet->type) {
    case EV_SYN:
        if (packet->code == SYN_REPORT)
            flush_source(source, packet->source_id, width, height);
        else if (packet->code == SYN_DROPPED)
            cancel_direct_touch(source);
        break;
    case EV_KEY:
        if (packet->value == 2)
            break;
        if (packet->value != 0 && packet->value != 1)
            return 0;
        if (packet->code == BTN_TOUCH && fake_input &&
            (source->flags & AURORA_INPUT_SOURCE_DIRECT)) {
            if (!(source->flags & AURORA_INPUT_SOURCE_MULTITOUCH)) {
                source->single_touch_pending_down = packet->value == 1;
                source->single_touch_pending_up = packet->value == 0;
            }
        } else if ((packet->code >= BTN_MOUSE &&
                    packet->code <= BTN_TASK) ||
                   packet->code == BTN_TOUCH) {
            uint32_t button = packet->code == BTN_TOUCH
                ? BTN_LEFT : packet->code;
            uint32_t state = packet->value
                ? WL_POINTER_BUTTON_STATE_PRESSED
                : WL_POINTER_BUTTON_STATE_RELEASED;
            if (fake_input)
                org_kde_kwin_fake_input_button(fake_input, button, state);
            if (virtual_pointer)
                zwlr_virtual_pointer_v1_button(
                    virtual_pointer, event_time_ms(), button, state);
        } else if (fake_input) {
            org_kde_kwin_fake_input_keyboard_key(
                fake_input, packet->code,
                packet->value ? WL_KEYBOARD_KEY_STATE_PRESSED
                              : WL_KEYBOARD_KEY_STATE_RELEASED);
        } else if (virtual_keyboard) {
            zwp_virtual_keyboard_v1_key(
                virtual_keyboard, event_time_ms(), packet->code,
                packet->value ? WL_KEYBOARD_KEY_STATE_PRESSED
                              : WL_KEYBOARD_KEY_STATE_RELEASED);
        }
        break;
    case EV_REL:
        if (packet->code == REL_X)
            source->relative_x += packet->value;
        else if (packet->code == REL_Y)
            source->relative_y += packet->value;
        else if (packet->code == REL_WHEEL)
            source->wheel_vertical += packet->value;
        else if (packet->code == REL_HWHEEL)
            source->wheel_horizontal += packet->value;
        else if (packet->code == REL_WHEEL_HI_RES)
            source->wheel_vertical_hi_res += packet->value;
        else if (packet->code == REL_HWHEEL_HI_RES)
            source->wheel_horizontal_hi_res += packet->value;
        break;
    case EV_ABS:
        if (fake_input && (source->flags & AURORA_INPUT_SOURCE_DIRECT) &&
            (source->flags & AURORA_INPUT_SOURCE_MULTITOUCH)) {
            struct aurora_touch_slot *slot = &source->slots[source->current_slot];
            if (packet->code == ABS_MT_SLOT) {
                if (packet->value >= 0 &&
                    packet->value < AURORA_MAX_TOUCH_SLOTS)
                    source->current_slot = packet->value;
            } else if (packet->code == ABS_MT_TRACKING_ID) {
                if (packet->value < 0) {
                    slot->pending_up = slot->active || slot->pending_down;
                    slot->pending_down = 0;
                    slot->tracking_id = -1;
                } else {
                    slot->tracking_id = packet->value;
                    slot->pending_down = 1;
                    slot->pending_up = 0;
                    slot->have_x = 0;
                    slot->have_y = 0;
                    slot->dirty = 0;
                }
            } else if (packet->code == ABS_MT_POSITION_X) {
                slot->x = packet->value;
                slot->minimum_x = packet->minimum;
                slot->maximum_x = packet->maximum;
                slot->have_x = 1;
                slot->dirty = 1;
            } else if (packet->code == ABS_MT_POSITION_Y) {
                slot->y = packet->value;
                slot->minimum_y = packet->minimum;
                slot->maximum_y = packet->maximum;
                slot->have_y = 1;
                slot->dirty = 1;
            }
        } else if (packet->code == ABS_X ||
                   packet->code == ABS_MT_POSITION_X) {
            source->absolute_x = packet->value;
            source->minimum_x = packet->minimum;
            source->maximum_x = packet->maximum;
            source->absolute_dirty = 1;
        } else if (packet->code == ABS_Y ||
                   packet->code == ABS_MT_POSITION_Y) {
            source->absolute_y = packet->value;
            source->minimum_y = packet->minimum;
            source->maximum_y = packet->maximum;
            source->absolute_dirty = 1;
        }
        break;
    default:
        break;
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 4 && argc != 5) {
        fprintf(stderr,
                "usage: %s FIFO WIDTH HEIGHT [ANDROID_TOUCH_SOCKET|-]\n",
                argv[0]);
        return 2;
    }
    const char *socket_path = argv[1];
    const char *touch_socket_path = argc == 5 ? argv[4] : "-";
    int width = atoi(argv[2]);
    int height = atoi(argv[3]);
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192)
        return 2;
    signal(SIGINT, stop_running);
    signal(SIGTERM, stop_running);

    struct wl_display *display = connect_wayland();
    if (!display) {
        fprintf(stderr, "aurora-input-proxy: KWin Wayland socket unavailable\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 ||
        initialize_input_protocols() != 0) {
        fprintf(stderr,
                "aurora-input-proxy: compositor has no supported input protocol\n");
        destroy_input_protocols();
        wl_registry_destroy(registry);
        wl_display_disconnect(display);
        return 1;
    }
    wl_display_flush(display);

    int input_pipe = create_pipe(socket_path);
    if (input_pipe < 0) {
        fprintf(stderr, "aurora-input-proxy: create FIFO %s: %s\n",
                socket_path, strerror(errno));
        destroy_input_protocols();
        wl_registry_destroy(registry);
        wl_display_disconnect(display);
        return 1;
    }
    fprintf(stderr, "aurora-input-proxy: ready fifo=%s geometry=%dx%d\n",
            socket_path, width, height);

    struct aurora_source_state sources[AURORA_INPUT_MAX_SOURCES] = {0};
    for (uint32_t source = 0; source < AURORA_INPUT_MAX_SOURCES; ++source) {
        for (uint32_t slot = 0; slot < AURORA_MAX_TOUCH_SLOTS; ++slot)
            sources[source].slots[slot].tracking_id = -1;
    }
    int result = 0;
    int touch_socket = -1;
    unsigned int reconnect_ticks = 0;
    while (running) {
        if (touch_socket < 0 && strcmp(touch_socket_path, "-") != 0 &&
            reconnect_ticks++ % 4 == 0)
            touch_socket = connect_touch_socket(touch_socket_path);

        struct pollfd items[2] = {
            {.fd = input_pipe, .events = POLLIN},
            {.fd = touch_socket, .events = POLLIN},
        };
        const nfds_t item_count = touch_socket >= 0 ? 2 : 1;
        int ready = poll(items, item_count, 250);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            result = 1;
            break;
        }
        if (ready == 0)
            continue;
        if (items[0].revents & (POLLERR | POLLNVAL)) {
            result = 1;
            break;
        }
        for (nfds_t index = 0; index < item_count; ++index) {
            if (index == 1 &&
                (items[index].revents & (POLLERR | POLLHUP | POLLNVAL))) {
                close(touch_socket);
                touch_socket = -1;
                reconnect_ticks = 0;
                fprintf(stderr,
                        "aurora-input-proxy: Android display touch disconnected\n");
                continue;
            }
            if (!(items[index].revents & POLLIN))
                continue;
            struct aurora_input_forward_packet packet;
            ssize_t received = read(items[index].fd, &packet, sizeof(packet));
            if (received < 0 && (errno == EAGAIN || errno == EINTR))
                continue;
            if (received != (ssize_t)sizeof(packet) ||
                dispatch_packet(&packet, sources, width, height) != 0 ||
                wl_display_flush(display) < 0) {
                if (index == 1) {
                    fprintf(stderr,
                            "aurora-input-proxy: rejected Android touch packet "
                            "bytes=%zd magic=0x%x version=%u size=%u "
                            "source=%u type=%u code=%u: %s\n",
                            received, packet.magic, packet.version,
                            packet.size, packet.source_id, packet.type,
                            packet.code, strerror(errno));
                    close(touch_socket);
                    touch_socket = -1;
                    reconnect_ticks = 0;
                    cancel_direct_touch(
                        &sources[AURORA_INPUT_ANDROID_TOUCH_SOURCE_ID - 1u]);
                    continue;
                }
                result = 1;
                break;
            }
        }
        if (result != 0)
            break;
    }
    if (touch_socket >= 0)
        close(touch_socket);
    close(input_pipe);
    destroy_input_protocols();
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return result;
}
