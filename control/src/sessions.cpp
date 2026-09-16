#include "aurora/control/sessions.hpp"

#include "aurora/control/system.hpp"

#include <algorithm>
#include <sstream>
#include <dirent.h>

namespace aurora::control {
namespace {

struct EnumSet {
    const char *key;
    std::vector<const char *> values;
};

const EnumSet kEnums[] = {
    {"backend", {"libhybris-hwcomposer", "android-presenter", "gralloc-minigbm",
                 "drm-kms", "nested-wayland", "headless"}},
    {"renderer", {"vendor-hybris", "native-mesa", "turnip-zink", "software"}},
    {"allocator", {"android-gralloc", "minigbm", "gbm", "none"}},
    {"presentation", {"internal-direct", "external-concurrent", "windowed",
                      "headless"}},
    {"input", {"evdev-grab", "external-bridge", "none"}},
    {"qualification", {"qualified", "proven", "experimental", "diagnostic",
                       "planned", "incompatible"}},
};

bool enum_allowed(const EnumSet &set, const std::string &value)
{
    return std::find(set.values.begin(), set.values.end(), value) !=
           set.values.end();
}

std::vector<std::string> csv(const std::string &value)
{
    std::vector<std::string> items;
    std::istringstream input(value);
    std::string item;
    while (std::getline(input, item, ',')) {
        item = trim(item);
        if (!item.empty()) items.push_back(item);
    }
    return items;
}

} // namespace

SessionFile load_session(const std::string &path)
{
    SessionFile file;
    const std::string text = read_file(path, 16U * 1024U);
    if (text.empty()) {
        file.errors.push_back("manifest missing or empty");
        return file;
    }
    SessionManifest &m = file.manifest;
    m.id = key_value(text, "id");
    m.title = key_value(text, "title");
    m.description = key_value(text, "description");
    m.backend = key_value(text, "backend");
    m.renderer = key_value(text, "renderer");
    m.allocator = key_value(text, "allocator");
    m.presentation = key_value(text, "presentation");
    m.input = key_value(text, "input");
    m.compositor = key_value(text, "compositor");
    m.shell = key_value(text, "shell");
    m.qualification = key_value(text, "qualification");
    m.reason = key_value(text, "reason");
    m.services = csv(key_value(text, "services"));
    m.requires_caps = csv(key_value(text, "requires"));
    m.limitations = csv(key_value(text, "limitations"));

    const std::size_t slash = path.rfind('/');
    const std::string base = slash == std::string::npos
        ? path : path.substr(slash + 1U);
    if (m.id.empty() || (base != m.id + ".session"))
        file.errors.push_back("id missing or filename mismatch");

    for (const EnumSet &set : kEnums) {
        const std::string value = [&] {
            if (set.key == std::string("backend")) return m.backend;
            if (set.key == std::string("renderer")) return m.renderer;
            if (set.key == std::string("allocator")) return m.allocator;
            if (set.key == std::string("presentation")) return m.presentation;
            if (set.key == std::string("input")) return m.input;
            return m.qualification;
        }();
        if (!enum_allowed(set, value))
            file.errors.push_back(std::string("invalid ") + set.key +
                                  ": " + (value.empty() ? "(missing)" : value));
    }
    const std::vector<std::string> structural = validate_manifest(m);
    file.errors.insert(file.errors.end(), structural.begin(), structural.end());
    return file;
}

std::vector<SessionFile> load_sessions(const std::string &directory)
{
    std::vector<SessionFile> files;
    DIR *dir = opendir(directory.c_str());
    if (!dir) return files;
    while (const dirent *entry = readdir(dir)) {
        const std::string name = entry->d_name;
        if (name.size() < 9U || name.substr(name.size() - 8U) != ".session")
            continue;
        files.push_back(load_session(directory + "/" + name));
    }
    closedir(dir);
    std::sort(files.begin(), files.end(),
              [](const SessionFile &a, const SessionFile &b) {
                  return a.manifest.id < b.manifest.id;
              });
    return files;
}

std::vector<std::string> validate_manifest(const SessionManifest &m)
{
    std::vector<std::string> errors;
    if (m.title.empty()) errors.push_back("title missing");
    if (m.compositor.empty() || m.compositor.front() != '/')
        errors.push_back("compositor must be an absolute guest path");
    if (!m.shell.empty() && m.shell.front() != '/')
        errors.push_back("shell must be empty or absolute");
    // An internal session that never touches Android gralloc is a lie on this
    // product: buffers come from the phone or not at all.
    if ((m.backend == "libhybris-hwcomposer" || m.backend == "gralloc-minigbm") &&
        m.allocator != "android-gralloc" && m.allocator != "minigbm")
        errors.push_back("android backends require android-gralloc/minigbm");
    if (m.backend == "nested-wayland" && m.presentation != "windowed")
        errors.push_back("nested sessions must present windowed");
    if (m.qualification == "incompatible" && m.reason.empty())
        errors.push_back("incompatible sessions must state why");
    if (m.qualification == "qualified" && m.requires_caps.empty())
        errors.push_back("qualified sessions must declare required capabilities");
    return errors;
}

SessionVerdict session_verdict(const SessionFile &file,
                               const CapabilityGraphOptions &capabilities)
{
    SessionVerdict verdict;
    verdict.id = file.manifest.id;
    verdict.status = file.manifest.qualification;
    verdict.blockers = file.errors;

    if (file.manifest.qualification == "planned") {
        verdict.blockers.push_back("session is planned, not built");
    }
    if (file.valid() && file.manifest.qualification != "planned") {
        const auto nodes = capability_graph(capabilities);
        for (const std::string &required : file.manifest.requires_caps) {
            const auto node = std::find_if(
                nodes.begin(), nodes.end(),
                [&](const CapabilityNode &n) { return n.id == required; });
            if (node == nodes.end()) {
                verdict.blockers.push_back("unknown capability " + required);
            } else if (!capability_status_at_least(node->status, "installed")) {
                verdict.blockers.push_back(
                    required + " is " + node->status +
                    (node->fallback.empty()
                         ? ""
                         : "; fallback: " + node->fallback));
            }
        }
        if (file.manifest.qualification == "experimental" ||
            file.manifest.qualification == "diagnostic") {
            verdict.blockers.push_back(
                file.manifest.qualification + " session; enable explicitly");
        }
    }
    verdict.launchable =
        verdict.status == "qualified" || verdict.status == "proven"
            ? verdict.blockers.empty()
            : false;
    return verdict;
}

std::string sessions_json(const std::vector<SessionFile> &files,
                          const CapabilityGraphOptions &capabilities)
{
    std::ostringstream output;
    output << "{\"schema\":2,\"sessions\":[";
    for (std::size_t index = 0; index < files.size(); ++index) {
        const SessionVerdict verdict = session_verdict(files[index], capabilities);
        const SessionManifest &m = files[index].manifest;
        if (index != 0) output << ',';
        output << "{\"id\":\"" << json_escape(m.id)
               << "\",\"title\":\"" << json_escape(m.title)
               << "\",\"description\":\"" << json_escape(m.description)
               << "\",\"backend\":\"" << json_escape(m.backend)
               << "\",\"renderer\":\"" << json_escape(m.renderer)
               << "\",\"allocator\":\"" << json_escape(m.allocator)
               << "\",\"presentation\":\"" << json_escape(m.presentation)
               << "\",\"input\":\"" << json_escape(m.input)
               << "\",\"qualification\":\"" << json_escape(m.qualification)
               << "\",\"reason\":\"" << json_escape(m.reason)
               << "\",\"launchable\":" << (verdict.launchable ? "true" : "false")
               << ",\"blockers\":[";
        for (std::size_t blocker = 0; blocker < verdict.blockers.size(); ++blocker) {
            if (blocker != 0) output << ',';
            output << '"' << json_escape(verdict.blockers[blocker]) << '"';
        }
        output << "],\"limitations\":[";
        for (std::size_t limit = 0; limit < m.limitations.size(); ++limit) {
            if (limit != 0) output << ',';
            output << '"' << json_escape(m.limitations[limit]) << '"';
        }
        output << "]}";
    }
    output << "]}";
    return output.str();
}

} // namespace aurora::control
