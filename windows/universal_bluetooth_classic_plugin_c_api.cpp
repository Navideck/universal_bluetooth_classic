#include "include/universal_bluetooth_classic/universal_bluetooth_classic_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "universal_bluetooth_classic_plugin.h"

void UniversalBluetoothClassicPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  universal_bluetooth_classic::UniversalBluetoothPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
