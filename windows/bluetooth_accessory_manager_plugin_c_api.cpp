#include "include/bluetooth_accessory_manager/bluetooth_accessory_manager_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "bluetooth_accessory_manager_plugin.h"

void BluetoothAccessoryManagerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  bluetooth_accessory_manager::BluetoothAccessoryManagerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
