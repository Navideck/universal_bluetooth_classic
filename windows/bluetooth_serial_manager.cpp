#include "bluetooth_serial_manager.h"

#include <winrt/Windows.Devices.Enumeration.h>

#include <cctype>
#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>

using namespace winrt;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::Rfcomm;
using namespace winrt::Windows::Devices::Enumeration;
using namespace winrt::Windows::Networking::Sockets;
using namespace winrt::Windows::Storage::Streams;

namespace universal_bluetooth_classic
{
    namespace serial = universal_bluetooth_classic_serial;

    namespace
    {
        uint64_t StrToMacAddress(const std::string &mac_str)
        {
            uint64_t mac_address_number = 0;
            uint8_t *mac_ptr = reinterpret_cast<uint8_t *>(&mac_address_number);
            int matched = sscanf_s(mac_str.c_str(), "%02hhx:%02hhx:%02hhx:%02hhx:%02hhx:%02hhx",
                                   &mac_ptr[5], &mac_ptr[4], &mac_ptr[3], &mac_ptr[2], &mac_ptr[1], &mac_ptr[0]);
            if (matched != 6)
            {
                // Without this check a malformed address silently becomes 0 (the
                // all-zero address) and is reported as "device not found".
                throw serial::FlutterError("InvalidAddress", "Invalid device address: " + mac_str);
            }
            return mac_address_number;
        }

        /// Parses a canonical UUID string (with or without dashes) into a GUID.
        guid ParseUuid(const std::string &uuid)
        {
            std::string hex;
            for (char c : uuid)
            {
                if (std::isxdigit(static_cast<unsigned char>(c)))
                {
                    hex += c;
                }
            }
            if (hex.size() != 32)
            {
                throw serial::FlutterError("InvalidUUID", "Invalid UUID: " + uuid);
            }

            uint8_t bytes[16] = {0};
            for (size_t i = 0; i < 16; i++)
            {
                bytes[i] = static_cast<uint8_t>(std::stoi(hex.substr(i * 2, 2), nullptr, 16));
            }

            uint32_t data1 = (static_cast<uint32_t>(bytes[0]) << 24) |
                             (static_cast<uint32_t>(bytes[1]) << 16) |
                             (static_cast<uint32_t>(bytes[2]) << 8) |
                             static_cast<uint32_t>(bytes[3]);
            uint16_t data2 = static_cast<uint16_t>((bytes[4] << 8) | bytes[5]);
            uint16_t data3 = static_cast<uint16_t>((bytes[6] << 8) | bytes[7]);
            std::array<uint8_t, 8> data4{};
            std::memcpy(data4.data(), bytes + 8, 8);
            return guid(data1, data2, data3, data4);
        }
    } // namespace

    BluetoothSerialManager::BluetoothSerialManager(flutter::PluginRegistrarWindows *registrar)
        : uiThreadHandler_(registrar)
    {
        callbackChannel_ = std::make_unique<serial::BluetoothSerialCallbackChannel>(registrar->messenger());
    }

    BluetoothSerialManager::~BluetoothSerialManager()
    {
        Dispose();
    }

    void BluetoothSerialManager::Connect(
        const std::string &device_id,
        const std::string &service_uuid,
        std::function<void(std::optional<serial::FlutterError> reply)> result)
    {
        bool already_connected = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            already_connected = sockets_.find(device_id) != sockets_.end();
        }
        if (already_connected)
        {
            // Like the Android and macOS managers, report the existing connection
            // instead of opening a second socket for the same device.
            PostConnectionState(device_id, true);
            result(std::nullopt);
            return;
        }

        ConnectAsync(device_id, service_uuid, std::move(result));
    }

    void BluetoothSerialManager::Disconnect(
        const std::string &device_id,
        std::function<void(std::optional<serial::FlutterError> reply)> result)
    {
        StreamSocket socket{nullptr};
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = sockets_.find(device_id);
            if (it != sockets_.end())
            {
                socket = it->second.socket;
                sockets_.erase(it);
            }
        }

        if (socket != nullptr)
        {
            try
            {
                socket.Close();
            }
            catch (...)
            {
            }
            PostConnectionState(device_id, false);
        }
        result(std::nullopt);
    }

    void BluetoothSerialManager::Send(
        const std::string &device_id,
        const std::vector<uint8_t> &data,
        std::function<void(std::optional<serial::FlutterError> reply)> result)
    {
        StreamSocket socket{nullptr};
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = sockets_.find(device_id);
            if (it != sockets_.end())
            {
                socket = it->second.socket;
            }
        }

        if (socket == nullptr)
        {
            result(serial::FlutterError("NotFound", "Device not connected"));
            return;
        }

        // The write can block, so it is performed off the platform thread.
        // Writes are queued and run one at a time so the bytes of overlapping
        // send() calls cannot interleave on the socket.
        {
            std::lock_guard<std::mutex> lock(mutex_);
            write_queue_.push_back(WriteRequest{socket, std::vector<uint8_t>(data), std::move(result)});
        }
        PumpWrites();
    }

    void BluetoothSerialManager::PumpWrites()
    {
        // Hold a reference for the whole write (and its continuation) so the
        // manager cannot be destroyed while a queued write is still pending.
        auto self = weak_from_this().lock();
        if (self == nullptr)
        {
            return;
        }

        WriteRequest request;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (writing_ || write_queue_.empty())
            {
                return;
            }
            writing_ = true;
            request = std::move(write_queue_.front());
            write_queue_.pop_front();
        }
        SendAsync(std::move(request.socket), std::move(request.data), std::move(request.result), std::move(self));
    }

    void BluetoothSerialManager::OnWriteComplete()
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            writing_ = false;
        }
        PumpWrites();
    }

    winrt::fire_and_forget BluetoothSerialManager::SendAsync(
        StreamSocket socket,
        std::vector<uint8_t> data,
        std::function<void(std::optional<serial::FlutterError> reply)> result,
        std::shared_ptr<BluetoothSerialManager> self)
    {
        try
        {
            DataWriter writer(socket.OutputStream());
            writer.WriteBytes(data);
            co_await writer.StoreAsync();
            writer.DetachStream();
            result(std::nullopt);
        }
        catch (const hresult_error &err)
        {
            std::cout << "Send failed: " << to_string(err.message()) << std::endl;
            result(serial::FlutterError("Failed", "Failed to send data"));
        }
        catch (...)
        {
            result(serial::FlutterError("Failed", "Failed to send data"));
        }

        self->OnWriteComplete();
    }

    void BluetoothSerialManager::Dispose()
    {
        std::unordered_map<std::string, SocketEntry> sockets;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            sockets.swap(sockets_);
            // Drop any writes that have not started yet; the engine is going away.
            write_queue_.clear();
        }
        for (auto &entry : sockets)
        {
            try
            {
                entry.second.socket.Close();
            }
            catch (...)
            {
            }
        }
    }

    winrt::fire_and_forget BluetoothSerialManager::ConnectAsync(
        std::string device_id,
        std::string service_uuid,
        std::function<void(std::optional<serial::FlutterError> reply)> result)
    {
        // Keep the manager (and with it the sockets and the callback channel)
        // alive for the whole coroutine, so it cannot be destroyed while this is
        // in flight.
        auto self = weak_from_this().lock();
        if (self == nullptr)
        {
            result(serial::FlutterError("Failed", "Serial manager is shutting down"));
            co_return;
        }

        try
        {
            auto uuid = ParseUuid(service_uuid);

            BluetoothDevice btDevice = co_await BluetoothDevice::FromBluetoothAddressAsync(StrToMacAddress(device_id));
            if (btDevice == nullptr)
            {
                result(serial::FlutterError("NotFound", "Device not found"));
                co_return;
            }

            // RfcommDeviceService is the documented way to resolve a service
            // UUID to a connectable RFCOMM endpoint. FromIdAsync runs the SDP
            // lookup for us.
            auto serviceUuid = RfcommServiceId::FromUuid(uuid);
            auto selector = RfcommDeviceService::GetDeviceSelectorForBluetoothDeviceAndServiceId(btDevice, serviceUuid);
            auto deviceInformations = co_await DeviceInformation::FindAllAsync(selector);
            if (deviceInformations.Size() == 0)
            {
                result(serial::FlutterError(
                    "ServiceNotFound",
                    "Service " + service_uuid + " not found on " + device_id));
                co_return;
            }

            RfcommDeviceService service =
                co_await RfcommDeviceService::FromIdAsync(deviceInformations.GetAt(0).Id());
            if (service == nullptr)
            {
                result(serial::FlutterError("ServiceNotFound", "Failed to access service " + service_uuid));
                co_return;
            }

            StreamSocket socket;
            co_await socket.ConnectAsync(service.ConnectionHostName(), service.ConnectionServiceName());

            uint64_t generation = 0;
            StreamSocket previous{nullptr};
            {
                std::lock_guard<std::mutex> lock(mutex_);
                generation = ++next_generation_;
                auto it = sockets_.find(device_id);
                if (it != sockets_.end())
                {
                    // A concurrent connect raced past the check in Connect().
                    // Close the socket it left behind so it is not leaked; its
                    // read loop ignores the close because the generation differs.
                    previous = it->second.socket;
                }
                sockets_[device_id] = SocketEntry{socket, generation};
            }
            if (previous != nullptr)
            {
                try
                {
                    previous.Close();
                }
                catch (...)
                {
                }
            }

            PostConnectionState(device_id, true);
            result(std::nullopt);

            ReadLoop(socket, device_id, generation);
        }
        catch (const winrt::hresult_error &err)
        {
            int32_t code = static_cast<int32_t>(err.code().value);
            result(serial::FlutterError(std::to_string(code), to_string(err.message())));
        }
        catch (const serial::FlutterError &err)
        {
            result(serial::FlutterError(err.code(), err.message()));
        }
        catch (...)
        {
            result(serial::FlutterError("Unknown error"));
        }
    }

    winrt::fire_and_forget BluetoothSerialManager::ReadLoop(StreamSocket socket, std::string device_id, uint64_t generation)
    {
        // See ConnectAsync: the read loop can outlive the plugin's reference.
        auto self = weak_from_this().lock();
        if (self == nullptr)
        {
            co_return;
        }

        try
        {
            DataReader reader(socket.InputStream());
            reader.InputStreamOptions(InputStreamOptions::Partial);
            while (true)
            {
                auto loaded = co_await reader.LoadAsync(1024);
                if (loaded == 0)
                {
                    break;
                }
                std::vector<uint8_t> buffer(loaded);
                reader.ReadBytes(buffer);
                PostData(device_id, std::move(buffer));
            }
            reader.DetachStream();
        }
        catch (const hresult_error &err)
        {
            std::cout << "Serial read loop ended for " << device_id << ": " << to_string(err.message()) << std::endl;
        }
        catch (...)
        {
        }

        bool removed = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            // Only tear down the connection this read loop opened. A fast
            // disconnect-then-reconnect could otherwise remove the newer socket.
            auto it = sockets_.find(device_id);
            if (it != sockets_.end() && it->second.generation == generation)
            {
                sockets_.erase(it);
                removed = true;
            }
        }
        if (removed)
        {
            PostConnectionState(device_id, false);
        }
    }

    void BluetoothSerialManager::PostConnectionState(const std::string &device_id, bool connected)
    {
        // Hold a reference until the posted callback has run, so the manager and
        // its callback channel outlive the hop to the platform thread.
        auto self = weak_from_this().lock();
        if (self == nullptr)
        {
            return;
        }
        uiThreadHandler_.Post([self, device_id, connected]()
                              { self->callbackChannel_->OnConnectionStateChanged(
                                    device_id, connected, []() {}, [](const serial::FlutterError &error)
                                    { std::cout << "onConnectionStateChanged error: " << error.message() << std::endl; }); });
    }

    void BluetoothSerialManager::PostData(const std::string &device_id, std::vector<uint8_t> data)
    {
        auto self = weak_from_this().lock();
        if (self == nullptr)
        {
            return;
        }
        uiThreadHandler_.Post([self, device_id, data = std::move(data)]()
                              { self->callbackChannel_->OnData(
                                    device_id, data, []() {}, [](const serial::FlutterError &error)
                                    { std::cout << "onData error: " << error.message() << std::endl; }); });
    }

} // namespace universal_bluetooth_classic
