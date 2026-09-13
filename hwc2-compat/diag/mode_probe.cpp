/*
 * mode_probe: enumerate HWC2 display configurations without presenting a
 * frame or changing the active mode by default.
 *
 * This is intentionally a source-level diagnostic rather than a build.sh
 * target.  The two declarations below are the existing Determination
 * extensions implemented by hwc2_compat_extra.cpp and exported by
 * libhwc2_compat_layer.so.
 */

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <vector>

#include "hwc2_compatibility_layer.h"

extern "C" int32_t hwc2_compat_display_get_configs(
        hwc2_compat_display_t* display, HWC2DisplayConfig* configs,
        int32_t capacity);

extern "C" hwc2_error_t hwc2_compat_display_set_active_config(
        hwc2_compat_display_t* display, hwc2_config_t config);

namespace {

constexpr std::chrono::seconds kHotplugTimeout(5);
constexpr int32_t kMaximumConfigs = 4096;

struct Options {
    bool showHelp = false;
    bool hasDisplay = false;
    bool hasConfig = false;
    hwc2_display_t display = 0;
    hwc2_config_t config = 0;
};

struct ProbeState {
    std::mutex mutex;
    std::condition_variable changed;
    std::vector<hwc2_display_t> connectedDisplays;
};

ProbeState* g_probeState = nullptr;

void rememberDisplay(hwc2_display_t display, bool connected)
{
    if (!g_probeState)
        return;

    std::lock_guard<std::mutex> lock(g_probeState->mutex);
    auto& displays = g_probeState->connectedDisplays;
    auto it = std::find(displays.begin(), displays.end(), display);
    if (connected) {
        if (it == displays.end())
            displays.push_back(display);
    } else if (it != displays.end()) {
        displays.erase(it);
    }
    g_probeState->changed.notify_all();
}

void onVsyncReceived(HWC2EventListener*, int32_t, hwc2_display_t, int64_t)
{
}

void onHotplugReceived(HWC2EventListener*, int32_t, hwc2_display_t display,
                       bool connected, bool)
{
    rememberDisplay(display, connected);
}

void onRefreshReceived(HWC2EventListener*, int32_t, hwc2_display_t)
{
}

HWC2EventListener kEventListener = {
    &onVsyncReceived,
    &onHotplugReceived,
    &onRefreshReceived,
};

void printUsage(const char* program)
{
    fprintf(stderr,
            "usage: %s [--display DISPLAY_ID] [--set-config CONFIG_ID]\n"
            "\n"
            "Enumerates every connected HWC2 display and its configs.\n"
            "The default run is read-only: no power, vsync, validate, present,\n"
            "or mode-selection calls are made.\n"
            "\n"
            "  --display ID       inspect only this display (default: all)\n"
            "  --set-config ID    explicitly request this config after listing it\n"
            "  --help             show this help\n",
            program);
}

bool parseUnsigned(const char* text, uint64_t maximum, uint64_t* value)
{
    if (!text || !text[0] || text[0] == '-')
        return false;

    errno = 0;
    char* end = nullptr;
    unsigned long long parsed = strtoull(text, &end, 0);
    if (errno == ERANGE || end == text || *end != '\0' || parsed > maximum)
        return false;

    *value = static_cast<uint64_t>(parsed);
    return true;
}

bool parseArguments(int argc, char** argv, Options* options)
{
    for (int i = 1; i < argc; ++i) {
        const char* argument = argv[i];
        if (!strcmp(argument, "--help") || !strcmp(argument, "-h")) {
            options->showHelp = true;
            continue;
        }

        if (!strcmp(argument, "--display") || !strcmp(argument, "--set-config")) {
            if (i + 1 >= argc) {
                fprintf(stderr, "%s requires an argument\n", argument);
                return false;
            }

            uint64_t value = 0;
            if (!strcmp(argument, "--display")) {
                if (options->hasDisplay ||
                    !parseUnsigned(argv[++i], UINT64_MAX, &value)) {
                    fprintf(stderr, "invalid or repeated --display value\n");
                    return false;
                }
                options->hasDisplay = true;
                options->display = static_cast<hwc2_display_t>(value);
            } else {
                if (options->hasConfig ||
                    !parseUnsigned(argv[++i], UINT32_MAX, &value)) {
                    fprintf(stderr, "invalid or repeated --set-config value\n");
                    return false;
                }
                options->hasConfig = true;
                options->config = static_cast<hwc2_config_t>(value);
            }
            continue;
        }

        fprintf(stderr, "unknown argument: %s\n", argument);
        return false;
    }
    return true;
}

void printConfig(const HWC2DisplayConfig& config, bool active)
{
    if (config.vsyncPeriod > 0) {
        const double hz = 1000000000.0 /
                          static_cast<double>(config.vsyncPeriod);
        printf("display=%" PRIu64 " config=%" PRIu32 " %dx%d "
               "vsync_period_ns=%" PRId64 " hz=%.3f%s\n",
               static_cast<uint64_t>(config.display),
               static_cast<uint32_t>(config.id), config.width, config.height,
               config.vsyncPeriod, hz, active ? " active" : "");
    } else {
        printf("display=%" PRIu64 " config=%" PRIu32 " %dx%d "
               "vsync_period_ns=%" PRId64 " hz=unknown%s\n",
               static_cast<uint64_t>(config.display),
               static_cast<uint32_t>(config.id), config.width, config.height,
               config.vsyncPeriod, active ? " active" : "");
    }
}

int inspectDisplay(hwc2_compat_device_t* device, hwc2_display_t displayId,
                   const Options& options)
{
    hwc2_compat_display_t* display =
            hwc2_compat_device_get_display_by_id(device, displayId);
    if (!display) {
        fprintf(stderr, "display=%" PRIu64 ": unable to acquire display\n",
                static_cast<uint64_t>(displayId));
        return 1;
    }

    HWC2DisplayConfig* activeConfig =
            hwc2_compat_display_get_active_config(display);
    hwc2_config_t activeId = 0;
    bool hasActiveConfig = activeConfig != nullptr;
    if (hasActiveConfig)
        activeId = activeConfig->id;

    int32_t count = hwc2_compat_display_get_configs(display, nullptr, 0);
    if (count <= 0 || count > kMaximumConfigs) {
        fprintf(stderr,
                "display=%" PRIu64 ": invalid config count=%" PRId32 "\n",
                static_cast<uint64_t>(displayId), count);
        free(activeConfig);
        hwc2_compat_device_destroy_display(device, display);
        return 1;
    }

    std::vector<HWC2DisplayConfig> configs(static_cast<size_t>(count));
    int32_t returned = hwc2_compat_display_get_configs(
            display, configs.data(), count);
    if (returned <= 0 || returned > count) {
        fprintf(stderr,
                "display=%" PRIu64 ": config enumeration returned=%" PRId32
                " for count=%" PRId32 "\n",
                static_cast<uint64_t>(displayId), returned, count);
        free(activeConfig);
        hwc2_compat_device_destroy_display(device, display);
        return 1;
    }

    printf("display=%" PRIu64 " configs=%" PRId32 " active=%s\n",
           static_cast<uint64_t>(displayId), returned,
           hasActiveConfig ? "known" : "unknown");

    bool requestedConfigFound = false;
    for (int32_t i = 0; i < returned; ++i) {
        const bool active = hasActiveConfig && configs[static_cast<size_t>(i)].id == activeId;
        printConfig(configs[static_cast<size_t>(i)], active);
        if (options.hasConfig && configs[static_cast<size_t>(i)].id == options.config)
            requestedConfigFound = true;
    }

    int result = 0;
    if (options.hasConfig) {
        if (!requestedConfigFound) {
            fprintf(stderr,
                    "display=%" PRIu64 ": requested config=%" PRIu32
                    " was not enumerated; no switch attempted\n",
                    static_cast<uint64_t>(displayId),
                    static_cast<uint32_t>(options.config));
            result = 1;
        } else if (hasActiveConfig && activeId == options.config) {
            printf("display=%" PRIu64 " config=%" PRIu32 " already active;"
                   " no switch needed\n",
                   static_cast<uint64_t>(displayId),
                   static_cast<uint32_t>(options.config));
        } else {
            hwc2_error_t error = hwc2_compat_display_set_active_config(
                    display, options.config);
            printf("display=%" PRIu64 " set_config=%" PRIu32 " rc=%d\n",
                   static_cast<uint64_t>(displayId),
                   static_cast<uint32_t>(options.config), error);
            if (error != HWC2_ERROR_NONE)
                result = 1;
        }
    }

    free(activeConfig);
    hwc2_compat_device_destroy_display(device, display);
    return result;
}

} // namespace

int main(int argc, char** argv)
{
    Options options;
    if (!parseArguments(argc, argv, &options)) {
        printUsage(argv[0]);
        return 2;
    }
    if (options.showHelp) {
        printUsage(argv[0]);
        return 0;
    }

    ProbeState state;
    g_probeState = &state;

    hwc2_compat_device_t* device = hwc2_compat_device_new(false);
    if (!device) {
        fprintf(stderr, "unable to create HWC2 compatibility device\n");
        return 1;
    }

    hwc2_compat_device_register_callback(device, &kEventListener, 0);
    {
        std::unique_lock<std::mutex> lock(state.mutex);
        state.changed.wait_for(lock, kHotplugTimeout, [&state] {
            return !state.connectedDisplays.empty();
        });
    }

    std::vector<hwc2_display_t> displays;
    {
        std::lock_guard<std::mutex> lock(state.mutex);
        displays = state.connectedDisplays;
    }
    std::sort(displays.begin(), displays.end());

    if (options.hasDisplay) {
        if (std::find(displays.begin(), displays.end(), options.display) == displays.end()) {
            fprintf(stderr, "requested display=%" PRIu64 " is not connected\n",
                    static_cast<uint64_t>(options.display));
            return 1;
        }
        displays.clear();
        displays.push_back(options.display);
    } else if (options.hasConfig && displays.size() != 1) {
        fprintf(stderr,
                "--set-config requires --display when %zu displays are connected\n",
                displays.size());
        return 2;
    }

    if (displays.empty()) {
        fprintf(stderr, "no connected HWC2 displays reported within %lld seconds\n",
                static_cast<long long>(kHotplugTimeout.count()));
        return 1;
    }

    int result = 0;
    for (hwc2_display_t display : displays)
        result |= inspectDisplay(device, display, options);
    return result;
}
