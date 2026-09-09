//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <universal_bluetooth_classic/universal_bluetooth_classic_plugin_c_api.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  UniversalBluetoothClassicPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UniversalBluetoothClassicPluginCApi"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
}
