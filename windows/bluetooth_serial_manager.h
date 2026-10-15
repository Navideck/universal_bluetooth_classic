#ifndef FLUTTER_PLUGIN_UNIVERSAL_BLUETOOTH_CLASSIC_SERIAL_MANAGER_H_
#define FLUTTER_PLUGIN_UNIVERSAL_BLUETOOTH_CLASSIC_SERIAL_MANAGER_H_

#include <flutter/plugin_registrar_windows.h>

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Rfcomm.h>
#include <winrt/Windows.Networking.Sockets.h>
#include <winrt/Windows.Storage.Streams.h>

#include <cstdint>
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
    ///
    /// Must be owned by a `std::shared_ptr`. The connect and read coroutines and
    /// the posted callbacks hold a reference to the manager, so a teardown that
    /// drops the plugin's reference cannot destroy it mid-flight.
    class BluetoothSerialManager
        : public universal_bluetooth_classic_serial::BluetoothSerialPlatformChannel,
          public std::enable_shared_from_this<BluetoothSerialManager>
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

        void Send(
            const std::string &device_id,
            const std::vector<uint8_t> &data,
            std::function<void(std::optional<universal_bluetooth_classic_serial::FlutterError> reply)> result) override;

        /// Closes every open connection, e.g. when the plugin is destroyed.
        void Dispose();

    private:
        winrt::fire_and_forget ConnectAsync(
            std::string device_id,
            std::string service_uuid,
            std::function<void(std::optional<universal_bluetooth_classic_serial::FlutterError> reply)> result);

        winrt::fire_and_forget SendAsync(
            winrt::Windows::Networking::Sockets::StreamSocket socket,
            std::vector<uint8_t> data,
            std::function<void(std::optional<universal_bluetooth_classic_serial::FlutterError> reply)> result);

        winrt::fire_and_forget ReadLoop(
            winrt::Windows::Networking::Sockets::StreamSocket socket,
            std::string device_id,
            uint64_t generation);

        void PostConnectionState(const std::string &device_id, bool connected);

        void PostData(const std::string &device_id, std::vector<uint8_t> data);

        /// A connected socket together with the id of the connect that opened
        /// it, so a stale read loop cannot tear down a newer connection.
        struct SocketEntry
        {
            winrt::Windows::Networking::Sockets::StreamSocket socket;
            uint64_t generation;
        };

        UiThreadHandler uiThreadHandler_;
        std::unique_ptr<universal_bluetooth_classic_serial::BluetoothSerialCallbackChannel> callbackChannel_;
        std::unordered_map<std::string, SocketEntry> sockets_;
        uint64_t next_generation_ = 0;
        std::mutex mutex_;
    };

} // namespace universal_bluetooth_classic

#endif
