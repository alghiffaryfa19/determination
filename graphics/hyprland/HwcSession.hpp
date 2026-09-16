#pragma once
#include <hybris/hwc2/hwc2_compatibility_layer.h>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <map>
#include <mutex>
#include <poll.h>
#include <set>
#include <stdexcept>
#include <string>
#include <sys/eventfd.h>
#include <unistd.h>
#include <utility>
#include <vector>

namespace Dethyprland {
template <class BufferPtr> class HwcSession {
  public:
    struct Output {
        std::string name;
        int width = 0, height = 0, refresh = 60000;
        uint64_t generation = 0;
    };
    static HwcSession& instance() {
        // libhwc2 cannot unregister callbacks; this owner lives until process exit.
        static auto* session = new HwcSession;
        return *session;
    }
    static bool enabled() {
        const char* value = std::getenv("AURORA_HYBRIS_HWC");
        return value && std::string(value) == "1";
    }
    static bool owns(const std::string& name) {
        return name == "HWC-1" || name.starts_with("HWC-EXT-");
    }
    int eventFd() const { return eventFd_; }
    std::vector<Output> outputs() const {
        std::vector<Output> result;
        for (const auto& [id, display] : displays_) {
            (void)id;
            result.push_back(display.output);
        }
        return result;
    }
    Output output(const std::string& name) const {
        for (const auto& [id, display] : displays_) {
            (void)id;
            if (display.output.name == name) return display.output;
        }
        return {};
    }
    bool takeFrame(const std::string& name) {
        auto* display = find(name);
        return display && std::exchange(display->frame, false);
    }
    void dispatch() {
        uint64_t value;
        while (read(eventFd_, &value, sizeof(value)) > 0) {}
        std::map<hwc2_display_t, bool> hotplug;
        std::set<hwc2_display_t> frames;
        {
            std::lock_guard lock(callbackMutex_);
            hotplug.swap(hotplug_);
            frames.swap(frames_);
        }
        for (const auto& [id, connected] : hotplug) {
            disconnect(id);
            hwc2_compat_device_on_hotplug(device_, id, connected);
            if (!connected) continue;
            try {
                connect(id);
            } catch (const std::exception& error) {
                disconnect(id);
                if (id == 0) throw;
                fprintf(stderr, "HWC display %llu unavailable: %s\n",
                        static_cast<unsigned long long>(id), error.what());
            }
        }
        for (auto id : frames) {
            auto it = displays_.find(id);
            if (it != displays_.end()) it->second.frame = true;
        }
    }
    bool present(const std::string& name, BufferPtr buffer, int producerFence) {
        auto* d = find(name);
        if (!d || !buffer || !buffer->androidNativeBuffer()) return false;
        // Initial modesets attach unrendered buffers and have no producer fence yet.
        if (producerFence < 0) {
            if (d->current) throw std::runtime_error("HWC frame missing producer fence");
            return true;
        }
        uint32_t types = 0, requests = 0;
        auto status = hwc2_compat_display_validate(d->display, &types, &requests);
        if ((status != HWC2_ERROR_NONE && status != HWC2_ERROR_HAS_CHANGES) || types || requests)
            return false;
        if (status == HWC2_ERROR_HAS_CHANGES &&
            hwc2_compat_display_accept_changes(d->display) != HWC2_ERROR_NONE) return false;
        int acquire = dup(producerFence);
        if (acquire < 0) throw std::runtime_error("HWC producer fence duplication failed");
        status = hwc2_compat_display_set_client_target(d->display, 0,
            static_cast<ANativeWindowBuffer*>(buffer->androidNativeBuffer()), acquire, HAL_DATASPACE_UNKNOWN);
        check(status, "client target");
        int retire = -1;
        status = hwc2_compat_display_present(d->display, &retire);
        if (status != HWC2_ERROR_NONE) {
            if (retire >= 0) close(retire);
            throw std::runtime_error("HWC present failed; refusing buffer reuse");
        }
        // HWC presents asynchronously. Waiting here turned every frame into a
        // compositor-thread round trip to the panel even when a new buffer was ready.
        // Keep the old target alive until its successor retires, and only block when
        // the bounded queue is full so a stalled composer cannot exhaust buffers.
        d->retired.push_back({d->current, retire});
        d->current = buffer;
        reapRetired(*d, false);
        while (d->retired.size() > maxRetiredFrames) reapRetired(*d, true);
        return true;
    }

  private:
    struct Display {
        struct Retired {
            BufferPtr buffer;
            int fence = -1;
        };
        Output output;
        hwc2_compat_display_t* display = nullptr;
        hwc2_compat_layer_t* layer = nullptr;
        BufferPtr current;
        std::deque<Retired> retired;
        bool frame = true;
    };
    static constexpr size_t maxRetiredFrames = 2;
    struct Callbacks : HWC2EventListener { HwcSession* owner; } callbacks_{};
    hwc2_compat_device_t* device_ = nullptr;
    int eventFd_ = -1;
    uint64_t generation_ = 0;
    std::map<hwc2_display_t, Display> displays_;
    std::mutex callbackMutex_;
    std::map<hwc2_display_t, bool> hotplug_;
    std::set<hwc2_display_t> frames_;

    Display* find(const std::string& name) {
        for (auto& [id, display] : displays_) {
            (void)id;
            if (display.output.name == name) return &display;
        }
        return nullptr;
    }
    static void reapRetired(Display& display, bool wait) {
        while (!display.retired.empty()) {
            auto& retired = display.retired.front();
            if (retired.fence < 0) {
                display.retired.pop_front();
                continue;
            }
            pollfd fd{retired.fence, POLLIN, 0};
            int result;
            do result = poll(&fd, 1, wait ? 1000 : 0); while (result < 0 && errno == EINTR);
            if (result == 0 && !wait) return;
            close(retired.fence);
            retired.fence = -1;
            if (result != 1 || !(fd.revents & POLLIN) || (fd.revents & (POLLERR | POLLNVAL)))
                throw std::runtime_error("HWC retire fence failed/timed out; refusing buffer reuse");
            display.retired.pop_front();
        }
    }
    void signal() { uint64_t value = 1; (void)write(eventFd_, &value, sizeof(value)); }
    static HwcSession* owner(HWC2EventListener* cb) { return static_cast<Callbacks*>(cb)->owner; }
    void frame(hwc2_display_t id) {
        {
            std::lock_guard lock(callbackMutex_);
            frames_.insert(id);
        }
        signal();
    }
    HwcSession() {
        eventFd_ = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
        if (eventFd_ < 0) throw std::runtime_error("HWC eventfd failed");
        callbacks_.owner = this;
        callbacks_.on_vsync_received = [](HWC2EventListener* cb, int32_t, hwc2_display_t id, int64_t) { owner(cb)->frame(id); };
        callbacks_.on_refresh_received = [](HWC2EventListener* cb, int32_t, hwc2_display_t id) { owner(cb)->frame(id); };
        callbacks_.on_hotplug_received = [](HWC2EventListener* cb, int32_t, hwc2_display_t id, bool connected, bool) {
            auto* p = owner(cb);
            // HWC calls stay on the compositor thread, never on its Binder callback thread.
            {
                std::lock_guard lock(p->callbackMutex_);
                p->hotplug_[id] = connected;
            }
            p->signal();
        };
        device_ = hwc2_compat_device_new(false);
        if (!device_) throw std::runtime_error("HWC composer client unavailable");
        hwc2_compat_device_register_callback(device_, &callbacks_, 0);
        for (int attempt = 0; !displays_.contains(0) && attempt < 50; ++attempt) {
            pollfd fd{eventFd_, POLLIN, 0};
            poll(&fd, 1, 100);
            dispatch();
        }
        if (!displays_.contains(0)) throw std::runtime_error("HWC internal display timeout");
    }
    void connect(hwc2_display_t id) {
        auto& d = displays_[id];
        // On SM8150 HIDL, ID 0 is internal. libhwc2's primary flag is true for every display.
        d.output.name = id == 0 ? "HWC-1" : "HWC-EXT-" + std::to_string(id);
        d.output.generation = ++generation_;
        d.display = hwc2_compat_device_get_display_by_id(device_, id);
        if (!d.display) throw std::runtime_error("HWC display missing");
        auto* config = hwc2_compat_display_get_active_config(d.display);
        if (!config) throw std::runtime_error("HWC active config missing");
        d.output.width = config->width;
        d.output.height = config->height;
        if (config->vsyncPeriod > 0) d.output.refresh = int(1000000000000LL / config->vsyncPeriod);
        free(config);
        d.layer = hwc2_compat_display_create_layer(d.display);
        if (!d.layer) throw std::runtime_error("HWC layer creation failed");
        check(hwc2_compat_layer_set_blend_mode(d.layer, HWC2_BLEND_MODE_NONE), "blend");
        check(hwc2_compat_layer_set_composition_type(d.layer, HWC2_COMPOSITION_CLIENT), "composition");
        check(hwc2_compat_layer_set_source_crop(d.layer, 0, 0, d.output.width, d.output.height), "crop");
        check(hwc2_compat_layer_set_display_frame(d.layer, 0, 0, d.output.width, d.output.height), "frame");
        check(hwc2_compat_layer_set_visible_region(d.layer, 0, 0, d.output.width, d.output.height), "region");
        check(hwc2_compat_display_set_power_mode(d.display, HWC2_POWER_MODE_ON), "power");
        if (id == 0) check(hwc2_compat_display_set_brightness(d.display, 1.0f), "brightness");
        check(hwc2_compat_display_set_vsync_enabled(d.display, HWC2_VSYNC_ENABLE), "vsync");
        fprintf(stderr, "HWC connected %s: %dx%d@%d\n", d.output.name.c_str(),
                d.output.width, d.output.height, d.output.refresh);
    }
    void disconnect(hwc2_display_t id) {
        auto it = displays_.find(id);
        if (it == displays_.end()) return;
        auto& d = it->second;
        fprintf(stderr, "HWC removed %s\n", d.output.name.c_str());
        for (auto& retired : d.retired) if (retired.fence >= 0) close(retired.fence);
        if (d.layer) hwc2_compat_display_destroy_layer(d.display, d.layer);
        if (d.display) hwc2_compat_device_destroy_display(device_, d.display);
        displays_.erase(it);
    }
    static void check(hwc2_error_t status, const char* operation) {
        if (status != HWC2_ERROR_NONE)
            throw std::runtime_error(std::string("HWC ") + operation + " failed: " + std::to_string(status));
    }
};
}
