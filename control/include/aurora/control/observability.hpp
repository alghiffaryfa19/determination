#pragma once

#include "aurora/control/state.hpp"

#include <string>

namespace aurora::control {

struct ObservabilityOptions {
    std::string root;
    bool observe_only = true;
};

bool presenter_socket_ready();
std::string status_payload(const ObservabilityOptions &options,
                           const StateRecord &state);
std::string doctor_payload(const ObservabilityOptions &options,
                           const StateRecord &state);
std::string metrics_payload(const ObservabilityOptions &options,
                            const StateRecord &state);
std::string capabilities_payload(const ObservabilityOptions &options,
                                 bool guest_endpoint);
std::string health_payload(const ObservabilityOptions &options,
                           const StateRecord &state);

} // namespace aurora::control
