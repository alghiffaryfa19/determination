#include "determination/control/capability.hpp"

#include "determination/control/observability.hpp"
#include "determination/control/system.hpp"

#include <algorithm>
#include <sstream>
#include <ctime>
#include <iterator>

namespace determination::control {
namespace {

struct SeedNode {
    const char *id;
    const char *probe;      // root-relative path that must exist
    const char *base;       // status when probe hits
    const char *fallback;
};

// Base statuses come from the installed toolkit; qualification overlays may
// only raise a status along the ladder or mark degraded/revoked with evidence.
constexpr SeedNode kSeeds[] = {
    {"display.internal.hwc", "bin/desktop-on", "installed", "nested-wayland"},
    {"display.external.presenter", "", "buildable", "internal-only"},
    {"renderer.vendor-hybris", "lxc/bin/lxc-info", "installed", "llvmpipe"},
    {"renderer.native-turnip", "", "buildable", "vendor-hybris"},
    {"session.phosh", "", "detected", "none"},
    {"session.plasma-mobile", "", "buildable", "phosh"},
    {"audio.speaker.direct", "bin/det-audio-owner", "installed", "android-audio"},
    {"audio.dp.direct", "", "buildable", "speaker-only"},
    {"input.touch.internal", "bin/evgrab", "installed", "none"},
    {"input.keyboard.external", "bin/external-input", "installed", "osk"},
    {"boot.linux-first.health-gated", "bin/boot-profile", "installed", "phone-first"},
};

const char *kStatuses[] = {"unavailable", "buildable", "detected", "installed",
                           "proven", "qualified", "degraded", "revoked"};

int status_rank(const std::string &status)
{
    for (int index = 0; index < 6; ++index) {
        if (status == kStatuses[index]) return index;
    }
    return -1; // degraded/revoked
}

bool presenter_ready() { return presenter_socket_ready(); }

CapabilityNode load_overlay(const std::string &directory,
                            CapabilityNode node)
{
    const std::string text = read_file(
        directory + "/" + node.id + ".conf", 4096);
    if (text.empty()) return node;

    const std::string overlay_status = key_value(text, "status");
    if (!overlay_status.empty() &&
        std::find_if(std::begin(kStatuses), std::end(kStatuses),
                     [&](const char *value) { return overlay_status == value; }) !=
            std::end(kStatuses)) {
        const int base_rank = status_rank(node.status);
        const int overlay_rank = status_rank(overlay_status);
        // Ladder can rise one published step per gate run; degraded/revoked win.
        if (overlay_rank >= 0 && (base_rank < 0 || overlay_rank > base_rank))
            node.status = overlay_status;
        else if (overlay_status == "degraded" || overlay_status == "revoked")
            node.status = overlay_status;
    }
    node.gate = key_value(text, "gate");
    const std::string evidence = key_value(text, "evidence");
    if (!evidence.empty()) node.evidence = evidence;
    else if (!node.gate.empty()) node.evidence = "device-observed";
    const std::string timestamp = key_value(text, "timestamp_ms");
    if (!timestamp.empty()) {
        const std::uint64_t stamp = std::strtoull(timestamp.c_str(), nullptr, 10);
        const std::uint64_t now = static_cast<std::uint64_t>(time(nullptr)) * 1000U;
        node.evidence_age_ms = now > stamp ? now - stamp : 0;
    }
    return node;
}

} // namespace

bool capability_status_at_least(const std::string &status, const char *floor)
{
    return status_rank(status) >= status_rank(floor) && status_rank(status) <= 5;
}

std::vector<CapabilityNode> capability_graph(const CapabilityGraphOptions &options)
{
    std::vector<CapabilityNode> nodes;
    for (const SeedNode &seed : kSeeds) {
        CapabilityNode node;
        node.id = seed.id;
        node.evidence = "host-static";
        bool present = true;
        if (seed.probe && *seed.probe != '\0') {
            present = path_exists(options.root + "/" + seed.probe);
        }
        node.status = present ? seed.base : "unavailable";
        if (node.id == "display.external.presenter" && presenter_ready())
            node.status = "installed";

        node.fallback = seed.fallback;
        if (node.id == "session.phosh") {
            node.dependencies = {"display.internal.hwc", "renderer.vendor-hybris",
                                 "input.touch.internal"};
        } else if (node.id == "session.plasma-mobile") {
            node.dependencies = {"display.internal.hwc", "renderer.native-turnip",
                                 "input.touch.internal"};
        } else if (node.id == "boot.linux-first.health-gated") {
            node.dependencies = {"renderer.vendor-hybris", "input.touch.internal"};
        }
        nodes.push_back(load_overlay(options.root + "/state/capabilities",
                                     std::move(node)));
    }
    return nodes;
}

std::string capabilities_graph_json(const std::vector<CapabilityNode> &nodes)
{
    std::ostringstream output;
    output << "{\"schema\":2,\"nodes\":[";
    for (std::size_t index = 0; index < nodes.size(); ++index) {
        const CapabilityNode &node = nodes[index];
        if (index != 0) output << ',';
        output << "{\"id\":\"" << json_escape(node.id)
               << "\",\"status\":\"" << json_escape(node.status)
               << "\",\"evidence\":\"" << json_escape(node.evidence)
               << "\",\"evidence_age_ms\":" << node.evidence_age_ms
               << ",\"gate\":\"" << json_escape(node.gate)
               << "\",\"fallback\":\"" << json_escape(node.fallback)
               << "\",\"dependencies\":[";
        for (std::size_t dep = 0; dep < node.dependencies.size(); ++dep) {
            if (dep != 0) output << ',';
            output << '"' << json_escape(node.dependencies[dep]) << '"';
        }
        output << "],\"conflicts\":[";
        for (std::size_t conflict = 0; conflict < node.conflicts.size(); ++conflict) {
            if (conflict != 0) output << ',';
            output << '"' << json_escape(node.conflicts[conflict]) << '"';
        }
        output << "]}";
    }
    output << "]}";
    return output.str();
}

} // namespace determination::control
