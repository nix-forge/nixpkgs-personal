#pragma once

#include <algorithm>
#include <cctype>
#include <string>
#include <string_view>
#include <vector>

namespace bar_icons {

inline bool isSymbolicPath(std::string_view path) {
  const auto slash = path.find_last_of('/');
  const auto filename = slash == std::string_view::npos ? path : path.substr(slash + 1);
  return filename.contains("-symbolic.") || path.contains("/symbolic/") || path.contains("/panel/")
      || path.contains("/status/");
}

// Symbolic artwork is deliberately chosen by naming convention and icon
// context. Ordinary app images must not be flattened into opaque silhouettes.
// Lookup is injected so the same policy can be checked independently of GL.
template <typename Lookup>
std::string resolve(const std::string& name, bool preferSymbolic, Lookup lookup) {
  if (name.empty()) {
    return {};
  }
  if (!preferSymbolic || name.front() == '/') {
    return lookup(name);
  }
  std::string lower = name;
  std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return std::tolower(c); });
  std::vector<std::string> bases{name};
  if (lower != name) {
    bases.push_back(lower);
  }
  for (const auto& base : bases) {
    for (const auto& candidate : {base + "-symbolic", "indicator-" + base, base + "-indicator",
                                  base + "-panel", base + "-tray"}) {
      std::string path = lookup(candidate);
      if (!path.empty() && isSymbolicPath(path)) {
        return path;
      }
    }
  }
  return lookup(name);
}

} // namespace bar_icons
