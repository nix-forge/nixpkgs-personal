#include "shell/bar/widgets/bar_icon_policy.h"

#include <cassert>
#include <iostream>
#include <map>

int main() {
  const std::map<std::string, std::string> icons{
      {"editor", "/theme/apps/editor.svg"},
      {"editor-symbolic", "/theme/symbolic/apps/editor-symbolic.svg"},
      {"messenger", "/theme/apps/messenger.svg"},
      {"indicator-messenger", "/theme/24x24/panel/indicator-messenger.svg"},
      {"music", "/theme/apps/music.svg"},
      {"music-tray", "/theme/apps/music-tray.svg"},
      {"/custom/icon.png", "/custom/icon.png"},
  };
  auto lookup = [&icons](const std::string& name) {
    const auto found = icons.find(name);
    return found == icons.end() ? std::string{} : found->second;
  };
  using bar_icons::resolve;
  assert(resolve("editor", true, lookup) == "/theme/symbolic/apps/editor-symbolic.svg");
  assert(resolve("editor", false, lookup) == "/theme/apps/editor.svg");
  assert(resolve("Messenger", true, lookup) == "/theme/24x24/panel/indicator-messenger.svg");
  assert(resolve("music", true, lookup) == "/theme/apps/music.svg");
  assert(resolve("/custom/icon.png", true, lookup) == "/custom/icon.png");
  assert(resolve("missing", true, lookup).empty());
  assert(resolve("", true, lookup).empty());
  assert(bar_icons::isSymbolicPath("/icons/scalable/status/service-playing.svg"));
  assert(!bar_icons::isSymbolicPath("/nix/store/symbolic-package/icons/apps/editor.svg"));
  assert(!bar_icons::isSymbolicPath("/icons/apps/editor.png"));
  auto sizedLookup = [](const std::string& name, int size) {
    if (name == "missing") {
      return std::string{};
    }
    const auto context = name == "app" ? "apps" : "panel";
    const auto extension = name == "bitmap" ? ".png" : ".svg";
    return "/theme/" + std::to_string(size) + "/" + context + "/" + name + extension;
  };
  assert(bar_icons::resolveStatus("status", 16, 48, sizedLookup) == "/theme/16/panel/status.svg");
  assert(bar_icons::resolveStatus("status", 20, 48, sizedLookup) == "/theme/20/panel/status.svg");
  assert(bar_icons::resolveStatus("bitmap", 16, 48, sizedLookup) == "/theme/48/panel/bitmap.png");
  assert(bar_icons::resolveStatus("app", 16, 48, sizedLookup) == "/theme/48/apps/app.svg");
  assert(bar_icons::resolveStatus("missing", 16, 48, sizedLookup).empty());
  std::cout << "Symbolic selection, logical status size, artwork fallback, and opt-out checks passed\n";
}
