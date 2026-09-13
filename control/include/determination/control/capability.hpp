#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace determination::control {

// One support-graph node per §3.2 of the transformative roadmap. Statuses
// derive from on-root observations plus optional qualification overlays at
// <root>/state/capabilities/<id>.conf written by gate runs.
struct CapabilityNode {
    std::string id;
    std::string status;      // see kCapabilityStatuses
    std::string evidence;    // host-static | emulator-tested | device-observed |
                             // interactive | stress-qualified | release-qualified
    std::uint64_t evidence_age_ms = 0;
    std::string gate;
    std::string fallback;
    std::vector<std::string> dependencies;
    std::vector<std::string> conflicts;
};

struct CapabilityGraphOptions {
    std::string root;
    bool guest_endpoint = false;
};

std::vector<CapabilityNode> capability_graph(const CapabilityGraphOptions &options);
std::string capabilities_graph_json(const std::vector<CapabilityNode> &nodes);

bool capability_status_at_least(const std::string &status, const char *floor);

} // namespace determination::control
