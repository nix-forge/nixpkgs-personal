#include "dbus/network/network_display.h"
#include "dbus/network/network_types.h"
#include "dbus/network/route_preference.h"

#include <cassert>
#include <string_view>
#include <vector>

int main() {
  using route_preference::DefaultRoute;
  using route_preference::selectInterface;
  assert(selectInterface(
             std::vector<DefaultRoute>{{4, 2, 100}, {4, 3, 600}, {6, 2, 100}, {6, 3, 600}}) == 2);
  assert(selectInterface(std::vector<DefaultRoute>{{4, 3, 600}, {6, 3, 600}}) == 3);
  assert(selectInterface(std::vector<DefaultRoute>{{4, 2, 100}, {6, 3, 100}}) == 0);
  assert(selectInterface(std::vector<DefaultRoute>{{4, 2, 600}, {4, 3, 100}, {6, 3, 100}}) == 3);
  assert(selectInterface(std::vector<DefaultRoute>{{4, 2, 100}, {4, 3, 100}, {6, 2, 100}}) == 0);
  assert(selectInterface(std::vector<DefaultRoute>{}) == 0);

  NetworkState wifi;
  wifi.kind = NetworkConnectivity::Wireless;
  wifi.connected = true;
  wifi.wirelessEnabled = true;
  wifi.signalStrength = 90;
  assert(std::string_view(network_display::glyphForState(wifi)) == "wifi");
  wifi.preferredWiredInterface = "eth0";
  assert(std::string_view(network_display::glyphForState(wifi)) == "ethernet");
  wifi.preferredWiredInterface.clear();
  assert(std::string_view(network_display::glyphForState(wifi)) == "wifi");
}
