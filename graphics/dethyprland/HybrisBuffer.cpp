#include "HybrisBuffer.hpp"

#include <GLES2/gl2.h>
#include <stdexcept>
#include <string>
#include <unistd.h>

#ifndef EGL_NATIVE_BUFFER_HYBRIS
#define EGL_NATIVE_BUFFER_HYBRIS 0x3140
#endif

namespace Dethyprland {
namespace {
template<typename T> T proc(const char* name) {
    auto fn = reinterpret_cast<T>(eglGetProcAddress(name));
    if (!fn) throw std::runtime_error(std::string("libhybris entry point missing: ") + name);
    return fn;
}
using Create = EGLBoolean (*)(EGLint, EGLint, EGLint, EGLint, EGLint*, EGLClientBuffer*);
using Release = EGLBoolean (*)(EGLClientBuffer);
using Info = void (*)(EGLClientBuffer, int*, int*);
using Lock = EGLBoolean (*)(EGLClientBuffer, EGLint, EGLint, EGLint, EGLint, EGLint, void**);
constexpr int READ_RARELY = 2;
constexpr int USAGE = READ_RARELY | 0x100 | 0x200 | 0x800;
}

HybrisBuffer::HybrisBuffer(EGLDisplay display, int width, int height)
    : display_(display), width_(width), height_(height) {
    if (display == EGL_NO_DISPLAY || width <= 0 || height <= 0)
        throw std::runtime_error("invalid Android buffer geometry/display");
    const auto create = proc<Create>("eglHybrisCreateNativeBuffer");
    const auto release = proc<Release>("eglHybrisReleaseNativeBuffer");
    const auto createImage = proc<PFNEGLCREATEIMAGEKHRPROC>("eglCreateImageKHR");
    (void)proc<PFNEGLDESTROYIMAGEKHRPROC>("eglDestroyImageKHR");
    (void)proc<Release>("eglHybrisUnlockNativeBuffer");
    if (!create(width, height, USAGE, 1, &stride_, &buffer_))
        throw std::runtime_error("Android gralloc allocation failed");
    const EGLint attrs[] = {EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
    image_ = createImage(display_, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_HYBRIS, buffer_, attrs);
    if (image_ == EGL_NO_IMAGE_KHR) {
        release(buffer_);
        buffer_ = nullptr;
        throw std::runtime_error("vendor EGL native-buffer import failed");
    }
}

HybrisBuffer::~HybrisBuffer() {
    if (locked_)
        reinterpret_cast<Release>(eglGetProcAddress("eglHybrisUnlockNativeBuffer"))(buffer_);
    if (image_ != EGL_NO_IMAGE_KHR)
        reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"))(display_, image_);
    if (buffer_)
        reinterpret_cast<Release>(eglGetProcAddress("eglHybrisReleaseNativeBuffer"))(buffer_);
}

void HybrisBuffer::handleCounts(int& ints, int& fds) const {
    proc<Info>("eglHybrisGetNativeBufferInfo")(buffer_, &ints, &fds);
}

void* HybrisBuffer::lockForRead() {
    if (locked_) throw std::runtime_error("Android buffer already CPU-locked");
    void* address = nullptr;
    if (!proc<Lock>("eglHybrisLockNativeBuffer")(buffer_, READ_RARELY, 0, 0, width_, height_, &address))
        throw std::runtime_error("Android buffer CPU lock failed");
    locked_ = true;
    return address;
}

void HybrisBuffer::unlock() {
    if (!locked_) throw std::runtime_error("Android buffer is not CPU-locked");
    if (!proc<Release>("eglHybrisUnlockNativeBuffer")(buffer_))
        throw std::runtime_error("Android buffer CPU unlock failed");
    locked_ = false;
}

int HybrisBuffer::exportRenderFence() const {
    const auto create = proc<PFNEGLCREATESYNCKHRPROC>("eglCreateSyncKHR");
    const auto destroy = proc<PFNEGLDESTROYSYNCKHRPROC>("eglDestroySyncKHR");
    const auto duplicate = proc<PFNEGLDUPNATIVEFENCEFDANDROIDPROC>("eglDupNativeFenceFDANDROID");
    EGLSyncKHR sync = create(display_, EGL_SYNC_NATIVE_FENCE_ANDROID, nullptr);
    if (sync == EGL_NO_SYNC_KHR) throw std::runtime_error("vendor render fence creation failed");
    glFlush();
    int fd = duplicate(display_, sync);
    destroy(display_, sync);
    if (fd < 0) throw std::runtime_error("vendor render fence export failed");
    return fd;
}

void HybrisBuffer::waitReleaseFence(int fd) const {
    if (fd == -1) return;
    if (fd < -1) throw std::runtime_error("invalid release fence");
    PFNEGLCREATESYNCKHRPROC create;
    PFNEGLDESTROYSYNCKHRPROC destroy;
    PFNEGLCLIENTWAITSYNCKHRPROC wait;
    try {
        create = proc<PFNEGLCREATESYNCKHRPROC>("eglCreateSyncKHR");
        destroy = proc<PFNEGLDESTROYSYNCKHRPROC>("eglDestroySyncKHR");
        wait = proc<PFNEGLCLIENTWAITSYNCKHRPROC>("eglClientWaitSyncKHR");
    } catch (...) {
        close(fd);
        throw;
    }
    const EGLint attrs[] = {EGL_SYNC_NATIVE_FENCE_FD_ANDROID, fd, EGL_NONE};
    EGLSyncKHR sync = create(display_, EGL_SYNC_NATIVE_FENCE_ANDROID, attrs);
    if (sync == EGL_NO_SYNC_KHR) {
        close(fd);
        throw std::runtime_error("vendor release fence import failed");
    }
    // Bound the bring-up wait; never recycle a buffer after timeout or error.
    EGLint result = wait(display_, sync, 0, 1000000000ULL);
    destroy(display_, sync);
    if (result != EGL_CONDITION_SATISFIED_KHR)
        throw std::runtime_error("vendor release fence wait failed/timed out");
}
}
