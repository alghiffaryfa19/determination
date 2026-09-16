#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace aurora::control {

// Durable operation journal under <root>/state/operations.jsonl so a
// transition ID can be inspected after the client died.
struct JournalEntry {
    std::uint64_t transition_id = 0;
    std::string target;
    std::string final_state;
    std::vector<std::string> steps;
    std::string error;
    std::uint64_t started_wall_ms = 0;
    std::uint64_t ended_wall_ms = 0;

    bool valid() const { return transition_id != 0; }
};

class OperationJournal {
public:
    explicit OperationJournal(std::string path);

    bool append(const JournalEntry &entry, std::string *error);
    // Newest first; empty id returns the most recent entries.
    std::vector<JournalEntry> query(std::uint64_t transition_id,
                                    std::size_t limit) const;

    static constexpr std::size_t kRotateBytes = 512U * 1024U;
    static constexpr std::size_t kDefaultQueryLimit = 20;

private:
    std::string path_;
};

std::string journal_entry_json(const JournalEntry &entry);

} // namespace aurora::control
