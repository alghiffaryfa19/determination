#define _GNU_SOURCE

/*
 * Root Android-side external input capture.
 *
 * Only USB and Bluetooth evdev devices are selected. Phone touch, power and
 * volume devices remain with Android as a guaranteed release path. Every open
 * external node is EVIOCGRAB'd, and all grabs disappear automatically if this
 * process or the guest proxy dies.
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "input-forward-protocol.h"

/* The final protocol source ID is reserved for MotionEvents forwarded by the
 * Android presenter. */
#define DET_MAX_INPUTS (DET_INPUT_MAX_SOURCES - 1u)
#define DET_BITS_PER_LONG (sizeof(unsigned long) * 8u)
#define DET_BIT_WORDS(maximum) (((maximum) / DET_BITS_PER_LONG) + 1u)

struct det_source {
    int fd;
    uint32_t id;
    uint32_t flags;
    char path[256];
};

static struct det_source sources[DET_MAX_INPUTS];
static size_t source_count;
static volatile sig_atomic_t running = 1;

static void stop_running(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static int connect_proxy(const char *path)
{
    if (!path || !*path) {
        errno = EINVAL;
        return -1;
    }
    for (int attempt = 0; attempt < 100 && running; ++attempt) {
        int fd = open(path, O_WRONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd >= 0)
            return fd;
        if (errno != ENXIO && errno != ENOENT)
            return -1;
        usleep(100000);
    }
    errno = ETIMEDOUT;
    return -1;
}

static int external_bus(unsigned short bus)
{
    return bus == BUS_USB || bus == BUS_BLUETOOTH;
}

static int bit_is_set(const unsigned long *bits, unsigned int bit)
{
    return (bits[bit / DET_BITS_PER_LONG] &
            (1ul << (bit % DET_BITS_PER_LONG))) != 0;
}

static uint32_t source_flags(int fd)
{
    unsigned long absolute[DET_BIT_WORDS(ABS_MAX)] = {0};
    unsigned long properties[DET_BIT_WORDS(INPUT_PROP_MAX)] = {0};
    uint32_t flags = 0;

    if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absolute)), absolute) >= 0) {
        if ((bit_is_set(absolute, ABS_X) && bit_is_set(absolute, ABS_Y)) ||
            (bit_is_set(absolute, ABS_MT_POSITION_X) &&
             bit_is_set(absolute, ABS_MT_POSITION_Y)))
            flags |= DET_INPUT_SOURCE_ABSOLUTE;
        if (bit_is_set(absolute, ABS_MT_POSITION_X) &&
            bit_is_set(absolute, ABS_MT_POSITION_Y) &&
            bit_is_set(absolute, ABS_MT_TRACKING_ID))
            flags |= DET_INPUT_SOURCE_MULTITOUCH;
    }
    if (ioctl(fd, EVIOCGPROP(sizeof(properties)), properties) >= 0 &&
        bit_is_set(properties, INPUT_PROP_DIRECT))
        flags |= DET_INPUT_SOURCE_DIRECT;
    return flags;
}

static int source_exists(const char *path)
{
    for (size_t i = 0; i < source_count; ++i) {
        if (strcmp(sources[i].path, path) == 0)
            return 1;
    }
    return 0;
}

static int add_source(const char *path)
{
    if (source_exists(path))
        return 0;
    if (source_count >= DET_MAX_INPUTS) {
        errno = EOVERFLOW;
        return -1;
    }
    int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
        return errno == ENOENT ? 0 : -1;
    struct input_id identity;
    if (ioctl(fd, EVIOCGID, &identity) != 0 ||
        !external_bus(identity.bustype)) {
        close(fd);
        return 0;
    }
    char name[128] = "?";
    ioctl(fd, EVIOCGNAME(sizeof(name)), name);
    if (ioctl(fd, EVIOCGRAB, (void *)1) != 0) {
        fprintf(stderr, "det-input-forwarder: grab %s (%s): %s\n",
                path, name, strerror(errno));
        close(fd);
        return -1;
    }
    struct det_source *source = &sources[source_count];
    source->fd = fd;
    source->id = (uint32_t)source_count + 1;
    source->flags = source_flags(fd);
    snprintf(source->path, sizeof(source->path), "%s", path);
    ++source_count;
    fprintf(stderr,
            "det-input-forwarder: captured %s (%s bus=0x%x id=%u "
            "absolute=%s direct-touch=%s multitouch=%s)\n",
            path, name, identity.bustype, source->id,
            source->flags & DET_INPUT_SOURCE_ABSOLUTE ? "yes" : "no",
            source->flags & DET_INPUT_SOURCE_DIRECT ? "yes" : "no",
            source->flags & DET_INPUT_SOURCE_MULTITOUCH ? "yes" : "no");
    return 0;
}

static void remove_source(size_t index)
{
    if (index >= source_count)
        return;
    ioctl(sources[index].fd, EVIOCGRAB, (void *)0);
    close(sources[index].fd);
    fprintf(stderr, "det-input-forwarder: released %s\n",
            sources[index].path);
    for (size_t i = index + 1; i < source_count; ++i)
        sources[i - 1] = sources[i];
    --source_count;
    for (size_t i = 0; i < source_count; ++i)
        sources[i].id = (uint32_t)i + 1;
}

static int scan_sources(void)
{
    struct dirent **entries = NULL;
    int count = scandir("/dev/input", &entries, NULL, alphasort);
    if (count < 0)
        return -1;
    int result = 0;
    for (int i = 0; i < count; ++i) {
        struct dirent *entry = entries[i];
        if (strncmp(entry->d_name, "event", 5) == 0) {
            char path[256];
            int length = snprintf(path, sizeof(path), "/dev/input/%s",
                                  entry->d_name);
            if (length <= 0 || (size_t)length >= sizeof(path) ||
                add_source(path) != 0)
                result = -1;
        }
        free(entry);
    }
    free(entries);
    return result;
}

static void release_sources(void)
{
    for (size_t i = 0; i < source_count; ++i) {
        ioctl(sources[i].fd, EVIOCGRAB, (void *)0);
        close(sources[i].fd);
        sources[i].fd = -1;
    }
    source_count = 0;
}

static int forward_event(int socket_fd, const struct det_source *source,
                         const struct input_event *event)
{
    struct det_input_forward_packet packet = {
        .magic = DET_INPUT_FORWARD_MAGIC,
        .version = DET_INPUT_FORWARD_VERSION,
        .size = sizeof(packet),
        .source_id = source->id,
        .type = event->type,
        .code = event->code,
        .value = event->value,
        .source_flags = source->flags,
    };
    if (event->type == EV_ABS) {
        struct input_absinfo info;
        if (ioctl(source->fd, EVIOCGABS(event->code), &info) == 0) {
            packet.minimum = info.minimum;
            packet.maximum = info.maximum;
        }
    }
    return write(socket_fd, &packet, sizeof(packet)) ==
                   (ssize_t)sizeof(packet)
        ? 0 : -1;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s PROXY_SOCKET\n", argv[0]);
        return 2;
    }
    signal(SIGINT, stop_running);
    signal(SIGTERM, stop_running);
    int proxy = connect_proxy(argv[1]);
    if (proxy < 0) {
        fprintf(stderr, "det-input-forwarder: open FIFO %s: %s\n",
                argv[1], strerror(errno));
        return 1;
    }
    if (scan_sources() != 0)
        fprintf(stderr, "det-input-forwarder: initial scan was incomplete\n");
    if (source_count == 0)
        fprintf(stderr,
                "det-input-forwarder: waiting for USB/Bluetooth input; "
                "phone controls remain excluded\n");

    struct pollfd poll_items[DET_MAX_INPUTS];
    while (running) {
        for (size_t i = 0; i < source_count; ++i) {
            poll_items[i].fd = sources[i].fd;
            poll_items[i].events = POLLIN;
            poll_items[i].revents = 0;
        }
        int ready = poll(poll_items, source_count, 1000);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        int changed = 0;
        for (size_t i = 0; i < source_count; ++i) {
            if (poll_items[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                remove_source(i);
                changed = 1;
                break;
            }
            if (!(poll_items[i].revents & POLLIN))
                continue;
            struct input_event events[32];
            ssize_t bytes = read(sources[i].fd, events, sizeof(events));
            if (bytes < 0 && (errno == EAGAIN || errno == EINTR))
                continue;
            if (bytes == 0 || (bytes < 0 && errno == ENODEV)) {
                remove_source(i);
                changed = 1;
                break;
            }
            if (bytes < 0 ||
                bytes % (ssize_t)sizeof(struct input_event) != 0) {
                running = 0;
                break;
            }
            size_t count = (size_t)bytes / sizeof(struct input_event);
            for (size_t event = 0; event < count; ++event) {
                if (forward_event(proxy, &sources[i], &events[event]) != 0) {
                    running = 0;
                    break;
                }
            }
        }
        if (!running)
            break;
        if (changed || scan_sources() != 0)
            continue;
    }
    release_sources();
    close(proxy);
    return running ? 1 : 0;
}
