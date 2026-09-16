#define _GNU_SOURCE
#include <dlfcn.h>
#include <linux/input.h>
#include <stdarg.h>
#include <sys/ioctl.h>

int ioctl(int fd, unsigned long request, ...)
{
    va_list ap;
    void *arg;
    va_start(ap, request);
    arg = va_arg(ap, void *);
    va_end(ap);
    if (request == EVIOCGRAB) return 0;
    static int (*real_ioctl)(int, unsigned long, ...) = 0;
    if (!real_ioctl) real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    return real_ioctl(fd, request, arg);
}
