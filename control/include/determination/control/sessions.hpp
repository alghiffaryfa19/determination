#pragma once

#include "determination/control/capability.hpp"

#include <string>
#include <vector>

namespace determination::control {

// Session manifests declare the real rendering/presentation path (§5.1) so no
// compositor is offered just because its binary exists.
struct SessionManifest {
    std::string id;
    std::string title;
    std::string description;
    std::string backend;
    std::string renderer;
    std::string allocator;
    std::string presentation;
    std::string input;
    std::string compositor;
    std::string shell;
    std::string qualification;   // qualified|proven|experimental|diagnostic|planned|incompatible
    std::string reason;
    std::vector<std::string> services;
    std::vector<std::string> requires_caps;
    std::vector<std::string> limitations;
};

struct SessionFile {
    SessionManifest manifest;
    std::vector<std::string> errors;
    bool valid() const { return errors.empty(); }
};

struct SessionVerdict {
    std::string id;
    bool launchable = false;
    std::string status;              // qualification label shown in UIs
    std::vector<std::string> blockers;
};

SessionFile load_session(const std::string &path);
std::vector<SessionFile> load_sessions(const std::string &directory);
std::vector<std::string> validate_manifest(const SessionManifest &manifest);
SessionVerdict session_verdict(const SessionFile &file,
                               const CapabilityGraphOptions &capabilities);
std::string sessions_json(const std::vector<SessionFile> &files,
                          const CapabilityGraphOptions &capabilities);

} // namespace determination::control
