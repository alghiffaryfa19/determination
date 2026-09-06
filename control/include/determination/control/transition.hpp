#pragma once

#include "determination/control/journal.hpp"
#include "determination/control/protocol.hpp"
#include "determination/control/state.hpp"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

namespace determination::control {

struct TransitionRequestResult {
    Status status = Status::InternalError;
    std::string message;
    StateRecord state;
};

struct TransitionCancelResult {
    Status status = Status::InternalError;
    std::string message;
    StateRecord state;
};

class TransitionController {
public:
    // Journal is optional; when present every accepted transition lands there
    // so operation IDs stay inspectable across client death.
    TransitionController(std::string root, bool allow_transitions,
                         OperationJournal *journal = nullptr);
    ~TransitionController();

    TransitionController(const TransitionController &) = delete;
    TransitionController &operator=(const TransitionController &) = delete;

    bool initialise(std::string *error);
    StateRecord snapshot() const;
    TransitionRequestResult request(Mode target, std::uint64_t request_id,
                                    std::uint32_t deadline_ms);
    // Safe cancellation: only the active transition, only mid-flight.
    TransitionCancelResult cancel(std::uint64_t transition_id);
    bool wait_for_idle(std::uint32_t timeout_ms);
    bool allow_transitions() const { return allow_transitions_; }

private:
    void worker(Mode target, std::uint64_t deadline_ms);
    bool persist_locked(std::string *error = nullptr);
    void begin_step(const std::string &step);
    void complete_step(const std::string &step, int adapter_status,
                       const std::string &output);
    void fail_transition(const std::string &step, int adapter_status,
                         const std::string &message, const std::string &output,
                         bool attempt_rollback);
    void journal_locked(const char *final_state);
    bool verify_target(Mode target, std::string *error) const;

    std::string root_;
    bool allow_transitions_ = false;
    OperationJournal *journal_ = nullptr;
    StateStore store_;
    mutable std::mutex mutex_;
    std::condition_variable idle_condition_;
    StateRecord state_;
    std::thread worker_;
    std::atomic<bool> cancelled_{false};
    bool worker_active_ = false;
};

} // namespace determination::control
