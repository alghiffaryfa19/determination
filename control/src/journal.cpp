#include "aurora/control/journal.hpp"

#include "aurora/control/system.hpp"

#include <sys/stat.h>

#include <algorithm>
#include <chrono>
#include <fstream>
#include <sstream>

namespace aurora::control {
namespace {

std::uint64_t number_field(const std::string &line, const std::string &key)
{
    const std::size_t at = line.find(key);
    if (at == std::string::npos) return 0;
    std::size_t begin = at + key.size();
    if (begin >= line.size() || line[begin] == '"') return 0;
    return std::strtoull(line.c_str() + begin, nullptr, 10);
}

std::string string_field(const std::string &line, const std::string &key)
{
    const std::size_t at = line.find(key);
    if (at == std::string::npos) return {};
    const std::size_t begin = at + key.size();
    const std::size_t end = line.find('"', begin);
    if (end == std::string::npos) return {};
    return line.substr(begin, end - begin);
}

std::vector<std::string> steps_field(const std::string &line)
{
    std::vector<std::string> steps;
    const std::size_t at = line.find("\"steps\":[");
    if (at == std::string::npos) return steps;
    const std::size_t begin = at + sizeof("\"steps\":[") - 1U;
    const std::size_t end = line.find(']', begin);
    if (end == std::string::npos) return steps;
    std::istringstream items(line.substr(begin, end - begin));
    std::string item;
    while (std::getline(items, item, ',')) {
        const std::size_t open = item.find('"');
        const std::size_t close = item.rfind('"');
        if (open != std::string::npos && close > open)
            steps.push_back(item.substr(open + 1U, close - open - 1U));
    }
    return steps;
}

} // namespace

OperationJournal::OperationJournal(std::string path) : path_(std::move(path)) {}

std::string journal_entry_json(const JournalEntry &entry)
{
    std::ostringstream output;
    output << "{\"schema\":2,\"transition_id\":" << entry.transition_id
           << ",\"target\":\"" << json_escape(entry.target)
           << "\",\"final_state\":\"" << json_escape(entry.final_state)
           << "\",\"steps\":[";
    for (std::size_t index = 0; index < entry.steps.size(); ++index) {
        if (index != 0) output << ',';
        output << '"' << json_escape(entry.steps[index]) << '"';
    }
    output << "],\"error\":\"" << json_escape(entry.error)
           << "\",\"started_wall_ms\":" << entry.started_wall_ms
           << ",\"ended_wall_ms\":" << entry.ended_wall_ms << "}";
    return output.str();
}

bool OperationJournal::append(const JournalEntry &entry, std::string *error)
{
    if (!entry.valid() || entry.steps.size() > 64U ||
        entry.error.size() > 4096U) {
        if (error) *error = "invalid journal entry";
        return false;
    }
    std::string parent_error;
    const std::size_t slash = path_.rfind('/');
    if (slash != std::string::npos &&
        !ensure_directory(path_.substr(0, slash), 0750, &parent_error)) {
        if (error) *error = parent_error;
        return false;
    }
    struct stat metadata {};
    if (stat(path_.c_str(), &metadata) == 0 &&
        static_cast<std::size_t>(metadata.st_size) > kRotateBytes) {
        std::string rotated = path_ + ".1";
        rename(path_.c_str(), rotated.c_str());
    }
    std::ofstream file(path_, std::ios::app);
    if (!file) {
        if (error) *error = "cannot open journal";
        return false;
    }
    file << journal_entry_json(entry) << '\n';
    if (!file.good()) {
        if (error) *error = "journal write failed";
        return false;
    }
    return true;
}

std::vector<JournalEntry> OperationJournal::query(
    std::uint64_t transition_id, std::size_t limit) const
{
    // Newest entries live at the tail; the read is bounded by rotation.
    const std::string text = read_file(path_, kRotateBytes + 64U * 1024U);
    std::vector<JournalEntry> matches;
    std::istringstream lines(text);
    std::string line;
    while (std::getline(lines, line)) {
        if (line.size() > kRotateBytes / 4U) continue;
        JournalEntry entry;
        entry.transition_id = number_field(line, "\"transition_id\":");
        if (entry.transition_id == 0) continue;
        if (transition_id != 0 && entry.transition_id != transition_id) continue;
        entry.target = string_field(line, "\"target\":\"");
        entry.final_state = string_field(line, "\"final_state\":\"");
        entry.error = string_field(line, "\"error\":\"");
        entry.started_wall_ms = number_field(line, "\"started_wall_ms\":");
        entry.ended_wall_ms = number_field(line, "\"ended_wall_ms\":");
        entry.steps = steps_field(line);
        matches.push_back(std::move(entry));
    }
    std::reverse(matches.begin(), matches.end());
    if (matches.size() > limit) matches.resize(limit);
    return matches;
}

} // namespace aurora::control
