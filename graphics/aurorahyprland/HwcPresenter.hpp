#pragma once
#include "AquamarineBuffer.hpp"
#include <hybris/hwc2/hwc2_compatibility_layer.h>
#include <atomic>
#include <cstdlib>
#include <poll.h>
#include <sys/eventfd.h>
#include <stdexcept>
#include <string>

namespace AuroraHyprland {
class HwcPresenter {
  public:
    static HwcPresenter& instance() {
        // libhwc2 has no callback-unregister/device-destroy API; callbacks live until process exit.
        static auto* presenter = new HwcPresenter;
        return *presenter;
    }
    static bool enabled() {
        const char* value = std::getenv("AURORA_HYBRIS_HWC");
        return value && std::string(value) == "1";
    }
    int width() const { return width_; }
    int height() const { return height_; }
    int refresh() const { return refresh_; }
    int eventFd() const { return eventFd_; }
    void drain() { uint64_t value; while (read(eventFd_, &value, sizeof(value)) > 0) {} }

    bool present(Hyprutils::Memory::CSharedPointer<Aquamarine::IBuffer> buffer, int producerFence) {
        if (!buffer->androidNativeBuffer() || !connected_) return false;
        // Initial modesets attach unrendered buffers and have no producer fence yet.
        if (producerFence < 0) {
            if (current_) throw std::runtime_error("HWC frame missing producer fence");
            return true;
        }
        uint32_t types = 0, requests = 0;
        auto status = hwc2_compat_display_validate(display_, &types, &requests);
        if ((status != HWC2_ERROR_NONE && status != HWC2_ERROR_HAS_CHANGES) || types || requests)
            return false;
        if (status == HWC2_ERROR_HAS_CHANGES && hwc2_compat_display_accept_changes(display_) != HWC2_ERROR_NONE)
            return false;
        int acquire = dup(producerFence);
        if (acquire < 0) throw std::runtime_error("HWC producer fence duplication failed");
        status = hwc2_compat_display_set_client_target(display_, 0,
            static_cast<ANativeWindowBuffer*>(buffer->androidNativeBuffer()), acquire, HAL_DATASPACE_UNKNOWN);
        if (status != HWC2_ERROR_NONE) throw std::runtime_error("HWC client target rejected");
        int retire = -1;
        status = hwc2_compat_display_present(display_, &retire);
        if (status != HWC2_ERROR_NONE) {
            if (retire >= 0) close(retire);
            throw std::runtime_error("HWC present failed; refusing buffer reuse");
        }
        // Retain both targets across the retire wait. A failed wait must end this session.
        auto previous = current_;
        current_ = buffer;
        if (retire >= 0) {
            pollfd fd{retire, POLLIN, 0};
            int result = poll(&fd, 1, 1000);
            close(retire);
            if (result != 1 || !(fd.revents & POLLIN) || (fd.revents & (POLLERR | POLLNVAL)))
                throw std::runtime_error("HWC retire fence failed/timed out; refusing buffer reuse");
        }
        return true;
    }

  private:
    struct Callbacks : HWC2EventListener { HwcPresenter* owner; } callbacks_{};
    hwc2_compat_device_t* device_ = nullptr;
    hwc2_compat_display_t* display_ = nullptr;
    hwc2_compat_layer_t* layer_ = nullptr;
    std::atomic<bool> connected_{false};
    std::atomic<uint64_t> displayId_{0};
    int eventFd_ = -1, width_ = 0, height_ = 0, refresh_ = 60000;
    Hyprutils::Memory::CSharedPointer<Aquamarine::IBuffer> current_;

    void signal() { uint64_t value = 1; (void)write(eventFd_, &value, sizeof(value)); }
    static HwcPresenter* owner(HWC2EventListener* cb) { return static_cast<Callbacks*>(cb)->owner; }
    HwcPresenter() {
        eventFd_ = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
        if (eventFd_ < 0) throw std::runtime_error("HWC eventfd failed");
        callbacks_.owner = this;
        callbacks_.on_vsync_received = [](HWC2EventListener* cb, int32_t, hwc2_display_t, int64_t) { owner(cb)->signal(); };
        callbacks_.on_refresh_received = [](HWC2EventListener* cb, int32_t, hwc2_display_t) { owner(cb)->signal(); };
        callbacks_.on_hotplug_received = [](HWC2EventListener* cb, int32_t, hwc2_display_t id, bool connected, bool primary) {
            auto* p = owner(cb);
            hwc2_compat_device_on_hotplug(p->device_, id, connected);
            if (!primary) return;
            p->displayId_ = id;
            p->connected_ = connected;
            p->signal();
        };
        device_ = hwc2_compat_device_new(false);
        if (!device_) throw std::runtime_error("HWC composer client unavailable");
        hwc2_compat_device_register_callback(device_, &callbacks_, 0);
        for (int attempt = 0; !connected_ && attempt < 50; ++attempt) {
            pollfd fd{eventFd_, POLLIN, 0};
            poll(&fd, 1, 100);
            drain();
        }
        if (!connected_) throw std::runtime_error("HWC primary display timeout");
        display_ = hwc2_compat_device_get_display_by_id(device_, displayId_);
        if (!display_) throw std::runtime_error("HWC display missing");
        auto* config = hwc2_compat_display_get_active_config(display_);
        if (!config) throw std::runtime_error("HWC active config missing");
        width_ = config->width; height_ = config->height;
        if (config->vsyncPeriod > 0) refresh_ = int(1000000000000LL / config->vsyncPeriod);
        free(config);
        layer_ = hwc2_compat_display_create_layer(display_);
        if (!layer_) throw std::runtime_error("HWC layer creation failed");
        check(hwc2_compat_layer_set_blend_mode(layer_, HWC2_BLEND_MODE_NONE));
        check(hwc2_compat_layer_set_composition_type(layer_, HWC2_COMPOSITION_CLIENT));
        check(hwc2_compat_layer_set_source_crop(layer_, 0, 0, width_, height_));
        check(hwc2_compat_layer_set_display_frame(layer_, 0, 0, width_, height_));
        check(hwc2_compat_layer_set_visible_region(layer_, 0, 0, width_, height_));
        check(hwc2_compat_display_set_power_mode(display_, HWC2_POWER_MODE_ON));
        check(hwc2_compat_display_set_brightness(display_, 1.0f));
        check(hwc2_compat_display_set_vsync_enabled(display_, HWC2_VSYNC_ENABLE));
    }
    static void check(hwc2_error_t status) {
        if (status != HWC2_ERROR_NONE) throw std::runtime_error("HWC setup operation failed");
    }
};
}
