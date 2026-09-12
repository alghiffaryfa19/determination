#pragma once

#include "HybrisBuffer.hpp"
#include <aquamarine/buffer/Buffer.hpp>

namespace AuroraHyprland {

// Only the native-buffer renderer may consume this; never advertise fake DMA-BUF planes.
class AquamarineBuffer final : public Aquamarine::IBuffer {
  public:
    AquamarineBuffer(EGLDisplay display, int width, int height)
        : native_(display, width, height) {
        size = Hyprutils::Math::Vector2D(width, height);
    }
    ~AquamarineBuffer() override { events.destroy.emit(); }

    Aquamarine::eBufferCapability caps() override { return Aquamarine::BUFFER_CAPABILITY_NONE; }
    Aquamarine::eBufferType type() override { return Aquamarine::BUFFER_TYPE_MISC; }
    void update(const Hyprutils::Math::CRegion&) override {}
    bool isSynchronous() override { return false; }
    bool good() override { return native_.image() != EGL_NO_IMAGE_KHR; }
    Aquamarine::SDMABUFAttrs dmabuf() override { return {}; }
    Aquamarine::SSHMAttrs shm() override { return {}; }

    void* androidNativeBuffer() override { return native_.nativeBuffer(); }
    HybrisBuffer& native() { return native_; }

  private:
    HybrisBuffer native_;
};

}
