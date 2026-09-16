#pragma once

#include <EGL/egl.h>
#include <EGL/eglext.h>

namespace Hyprland {

// Keep the Android object intact: a pixel dma-buf cannot represent QTI metadata.
class HybrisBuffer final {
  public:
    HybrisBuffer(EGLDisplay display, int width, int height);
    ~HybrisBuffer();
    HybrisBuffer(const HybrisBuffer&) = delete;
    HybrisBuffer& operator=(const HybrisBuffer&) = delete;

    EGLClientBuffer nativeBuffer() const { return buffer_; }
    EGLImageKHR image() const { return image_; }
    int stride() const { return stride_; }
    void handleCounts(int& ints, int& fds) const;
    void* lockForRead();
    void unlock();

    // The caller owns the exported sync-file. Import consumes fd even on error.
    int exportRenderFence() const;
    void waitReleaseFence(int fd) const;

  private:
    EGLDisplay display_;
    EGLClientBuffer buffer_ = nullptr;
    EGLImageKHR image_ = EGL_NO_IMAGE_KHR;
    int width_, height_, stride_ = 0;
    bool locked_ = false;
};

}
