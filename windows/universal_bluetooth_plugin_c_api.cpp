#include "include/universal_bluetooth/universal_bluetooth_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "universal_bluetooth_plugin.h"

void UniversalBluetoothPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  universal_bluetooth::UniversalBluetoothPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
