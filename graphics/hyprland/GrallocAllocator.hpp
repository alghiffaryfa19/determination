#pragma once

#include "AquamarineBuffer.hpp"
#include <aquamarine/allocator/Allocator.hpp>
#include <aquamarine/backend/Backend.hpp>
#include <cmath>
#include <stdexcept>

namespace Hyprland {
class GrallocAllocator final : public Aquamarine::IAllocator {
  public:
    explicit GrallocAllocator(Hyprutils::Memory::CSharedPointer<Aquamarine::CBackend> backend)
        : backend_(backend) {
        display_ = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display_ == EGL_NO_DISPLAY || !eglInitialize(display_, nullptr, nullptr) ||
            !eglGetProcAddress("eglHybrisCreateNativeBuffer"))
            throw std::runtime_error("Hyprland requires vendor EGL through libhybris");
    }
    Hyprutils::Memory::CSharedPointer<Aquamarine::IBuffer> acquire(
        const Aquamarine::SAllocatorBufferParams& p,
        Hyprutils::Memory::CSharedPointer<Aquamarine::CSwapchain>) override {
        if (p.cursor || p.multigpu || (p.format != DRM_FORMAT_INVALID && p.format != DRM_FORMAT_ABGR8888) ||
            p.size.x < 1 || p.size.y < 1 || p.size.x > 16384 || p.size.y > 16384 ||
            std::floor(p.size.x) != p.size.x || std::floor(p.size.y) != p.size.y)
            return nullptr;
        try {
            return Hyprutils::Memory::makeShared<AquamarineBuffer>(display_, int(p.size.x), int(p.size.y));
        } catch (const std::exception& error) {
            if (auto backend = backend_.lock()) backend->log(Aquamarine::AQ_LOG_ERROR, error.what());
            return nullptr;
        }
    }
    Hyprutils::Memory::CSharedPointer<Aquamarine::CBackend> getBackend() override { return backend_.lock(); }
    int drmFD() override { return -1; }
    Aquamarine::eAllocatorType type() override { return Aquamarine::AQ_ALLOCATOR_TYPE_ANDROID; }

  private:
    Hyprutils::Memory::CWeakPointer<Aquamarine::CBackend> backend_;
    EGLDisplay display_ = EGL_NO_DISPLAY;
};
}
