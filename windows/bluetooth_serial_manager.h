#ifndef FLUTTER_PLUGIN_UNIVERSAL_BLUETOOTH_CLASSIC_SERIAL_MANAGER_H_
#define FLUTTER_PLUGIN_UNIVERSAL_BLUETOOTH_CLASSIC_SERIAL_MANAGER_H_

#include <flutter/plugin_registrar_windows.h>

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Rfcomm.h>
#include <winrt/Windows.Networking.Sockets.h>
#include <winrt/Windows.Storage.Streams.h>

#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "BluetoothSerialManager.g.h"
#include "ui_thread_handler.hpp"

namespace universal_bluetooth_classic
{
    /// Generic serial (SPP/RFCOMM) transport. Opens a StreamSocket to a
    /// RfcommDeviceService for the requested UUID and forwards the byte stream
    /// to Flutter.
    class BluetoothSerialManager
        : public universal_bluetooth_classic_serial::BluetoothSerialPlatformChannel
    {
    public:
        explicit BluetoothSerialManager(flutter::PluginRegistrarWindows *registrar);
        ~BluetoothSerialManager() override;

        BluetoothSerialManager(const BluetoothSerialManager &) = delete;
        BluetoothSerialManager &operator=(const BluetoothSerialManager &) = delete;

        void Connect(
            const std::string &device_id,
            const std::string &service_uuid,
            std::function<void(std::optional<universal_bluetooth_classic_serial::FlutterError> reply)> result) override;

        void Disconnect(
            const std::string &device_id,
            std::function<void(std::optional<universal_bluetooth_classic_serial::FlutterError> reply)> result) override;

        std::optional<universal_bluetooth_classic_serial::FlutterError> Send(
            const std::string &device_id,
            const std::vector<uint8_t> &data) override;

        /// Closes every open connection, e.g. when the plugin is destroyed.
        void Dispose();

    private:
        winrt::fire_and_forget ConnectAsync(
            std::string device_id,
            std::string service_uuid,
            std::function<void(std::optional<universal_bluetooth_classic_serial::FlutterError> reply)> result);

        winrt::fire_and_forget ReadLoop(
            winrt::Windows::Networking::Sockets::StreamSocket socket,
            std::string device_id);

        void PostConnectionState(const std::string &device_id, bool connected);

        void PostData(const std::string &device_id, std::vector<uint8_t> data);

        UiThreadHandler uiThreadHandler_;
        std::unique_ptr<universal_bluetooth_classic_serial::BluetoothSerialCallbackChannel> callbackChannel_;
        std::unordered_map<std::string, winrt::Windows::Networking::Sockets::StreamSocket> sockets_;
        std::mutex mutex_;
    };

} // namespace universal_bluetooth_classic

#endif
