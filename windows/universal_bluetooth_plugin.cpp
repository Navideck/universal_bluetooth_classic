#include "universal_bluetooth_plugin.h"

#include <windows.h>
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include "pin_entry.h"

namespace universal_bluetooth
{
  const auto isConnectableKey = L"System.Devices.Aep.Bluetooth.Le.IsConnectable";
  const auto isConnectedKey = L"System.Devices.Aep.IsConnected";
  const auto isPairedKey = L"System.Devices.Aep.IsPaired";
  const auto isPresentKey = L"System.Devices.Aep.IsPresent";
  const auto deviceAddressKey = L"System.Devices.Aep.DeviceAddress";
  const auto signalStrengthKey = L"System.Devices.Aep.SignalStrength";

  std::unique_ptr<FlutterAccessoryCallbackChannel> callbackChannel;

  void UniversalBluetoothPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto plugin = std::make_unique<UniversalBluetoothPlugin>(registrar);
    FlutterAccessoryPlatformChannel::SetUp(registrar->messenger(), plugin.get());
    callbackChannel = std::make_unique<FlutterAccessoryCallbackChannel>(registrar->messenger());
    registrar->AddPlugin(std::move(plugin));
  }

  UniversalBluetoothPlugin::UniversalBluetoothPlugin(flutter::PluginRegistrarWindows *registrar)
      : uiThreadHandler_(registrar)
  {
  }

  UniversalBluetoothPlugin::~UniversalBluetoothPlugin() {}

  void UniversalBluetoothPlugin::ShowBluetoothAccessoryPicker(
      const flutter::EncodableList &with_names,
      std::function<void(std::optional<FlutterError> reply)> result)
  {
    ShowDevicePicker(result);
  }

  // void UniversalBluetoothPlugin::Disconnect(const std::string &device_id,std::function<void(std::optional<FlutterError> reply)> result)
  // {
  //   DisconnectAsync(device_id, result);
  // }

  std::optional<FlutterError> UniversalBluetoothPlugin::StartScan()
  {
    try
    {
      setupDeviceWatcher();
      auto status = deviceWatcher.Status();
      std::cout << "StartingScan, CurrentState: " << DeviceWatcherStatusToString(status) << std::endl;
      if (status != DeviceWatcherStatus::Started)
      {
        deviceWatcher.Start();
      }
      restartEnumeration = true;
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "StartScan: " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      return FlutterError(std::to_string(errorCode), winrt::to_string(err.message()));
    }
    catch (...)
    {
      std::cout << "Unknown error StartScan" << std::endl;
      return FlutterError("Unknown error");
    }

    return std::nullopt;
  }

  std::optional<FlutterError> UniversalBluetoothPlugin::StopScan()
  {
    try
    {
      restartEnumeration = false;
      if (deviceWatcher != nullptr)
      {
        auto status = deviceWatcher.Status();
        std::cout << "StoppingScan, CurrentState: " << DeviceWatcherStatusToString(status) << std::endl;

        if (deviceWatcher.Status() == DeviceWatcherStatus::Started)
        {
          deviceWatcher.Stop();
        }
        deviceWatcher.Added(deviceWatcherAddedToken);
        deviceWatcher.Updated(deviceWatcherUpdatedToken);
        deviceWatcher.Removed(deviceWatcherRemovedToken);
        deviceWatcher.EnumerationCompleted(deviceWatcherEnumerationCompletedToken);
        deviceWatcher.Stopped(deviceWatcherStoppedToken);
        deviceWatcher = nullptr;
        deviceWatcherDevices.clear();
      }
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "StartScan: " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      return FlutterError(std::to_string(errorCode), winrt::to_string(err.message()));
    }
    catch (...)
    {
      std::cout << "Unknown error StartScan" << std::endl;
      return FlutterError("Unknown error");
    }
    return std::nullopt;
  }

  ErrorOr<bool> UniversalBluetoothPlugin::IsScanning()
  {
    if (deviceWatcher == nullptr)
    {
      return false;
    }
    auto status = deviceWatcher.Status();
    std::cout << "CurrentState: " << DeviceWatcherStatusToString(status) << std::endl;
    return status != DeviceWatcherStatus::Stopped;
  }

  ErrorOr<flutter::EncodableList> UniversalBluetoothPlugin::GetPairedDevices()
  {
    try
    {
      auto selector = Devices::Bluetooth::BluetoothDevice::GetDeviceSelectorFromPairingState(true);
      Enumeration::DeviceInformationCollection devices = async_get(Enumeration::DeviceInformation::FindAllAsync(selector));
      flutter::EncodableList results = flutter::EncodableList();
      for (auto &&deviceInfo : devices)
      {
        try
        {
          auto device = DeviceInfoToBluetoothDevice(deviceInfo);
          results.push_back(flutter::CustomEncodableValue(device));
        }
        catch (...)
        {
        }
      }
      return results;
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "GetPairedDevices: " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      return FlutterError(std::to_string(errorCode), winrt::to_string(err.message()));
    }
    catch (...)
    {
      std::cout << "Unknown error GetPairedDevices" << std::endl;
      return FlutterError("Unknown error");
    }
  }

  void UniversalBluetoothPlugin::Pair(
      const std::string &address,
      std::function<void(ErrorOr<bool> reply)> result)
  {
    try
    {
      if (isWindows11OrGreater())
      {
        PairAsync(address, result);
      }
      else
      {
        CustomPairAsync(address, result);
      }
    }
    catch (const FlutterError &err)
    {
      result(err);
    }
  }

  void UniversalBluetoothPlugin::Unpair(const std::string &address, std::function<void(std::optional<FlutterError> reply)> result)
  {
    UnPairAsync(address, result);
  }

  // Helper methods
  void UniversalBluetoothPlugin::setupDeviceWatcher()
  {
    if (deviceWatcher != nullptr)
      return;

    // Filter Paired or Unpaired Classic+Ble Devices
    // using Ble filter as well to increase enumeration time
    auto selector = L"((" + Bluetooth::BluetoothDevice::GetDeviceSelectorFromPairingState(true) +
                    L") OR (" +
                    Bluetooth::BluetoothLEDevice::GetDeviceSelectorFromPairingState(true) +
                    L")) OR ((" +
                    Bluetooth::BluetoothDevice::GetDeviceSelectorFromPairingState(false) +
                    L") OR (" +
                    Bluetooth::BluetoothLEDevice::GetDeviceSelectorFromPairingState(false) + L"))";

    deviceWatcher = DeviceInformation::CreateWatcher(
        selector,
        {
            deviceAddressKey,
            isConnectedKey,
            isPairedKey,
            isPresentKey,
            isConnectableKey,
            signalStrengthKey,
        },
        DeviceInformationKind::AssociationEndpoint);

    deviceWatcherAddedToken = deviceWatcher.Added([this](DeviceWatcher sender, DeviceInformation deviceInfo)
                                                  {
                                                    auto deviceInfoId = deviceInfo.Id();
                                                    std::string deviceId = winrt::to_string(deviceInfoId);
                                                    if (isBluetoothClassic(deviceInfoId))
                                                    {
                                                      deviceWatcherDevices.insert_or_assign(deviceId, deviceInfo);
                                                      auto device = DeviceInfoToBluetoothDevice(deviceInfo);
                                                      uiThreadHandler_.Post([device]
                                                                            { callbackChannel->OnDeviceDiscover(device, SuccessCallback, ErrorCallback); });
                                                    }
                                                    // On Device Added
                                                  });

    deviceWatcherUpdatedToken = deviceWatcher.Updated([this](DeviceWatcher sender, DeviceInformationUpdate deviceInfoUpdate)
                                                      {
                                                        std::string deviceId = winrt::to_string(deviceInfoUpdate.Id());
                                                        auto it = deviceWatcherDevices.find(deviceId);
                                                        if (it != deviceWatcherDevices.end())
                                                        {
                                                          it->second.Update(deviceInfoUpdate);
                                                          auto device = DeviceInfoToBluetoothDevice(it->second);
                                                          uiThreadHandler_.Post([device]
                                                                                { callbackChannel->OnDeviceDiscover(device, SuccessCallback, ErrorCallback); });
                                                        }
                                                        // On Device Updated
                                                      });

    deviceWatcherRemovedToken = deviceWatcher.Removed([this](DeviceWatcher sender, DeviceInformationUpdate args)
                                                      {
                                                        std::string deviceId = winrt::to_string(args.Id());
                                                        auto it = deviceWatcherDevices.find(deviceId);
                                                        if (it != deviceWatcherDevices.end())
                                                        {
                                                          auto device = DeviceInfoToBluetoothDevice(it->second);
                                                          uiThreadHandler_.Post([device]
                                                                                { callbackChannel->OnDeviceRemoved(device, SuccessCallback, ErrorCallback); });
                                                          deviceWatcherDevices.erase(deviceId);
                                                        }

                                                        // On Device Removed
                                                      });

    deviceWatcherEnumerationCompletedToken = deviceWatcher.EnumerationCompleted([this](DeviceWatcher sender, IInspectable args)
                                                                                {
                                                                                  std::cout << "DeviceWatcherEvent: EnumerationCompleted, Restart: " << restartEnumeration << std::endl;
                                                                                  // Enumeration Completed, restart scan if needed
                                                                                  if(restartEnumeration){
                                                                                    // Stop and Start Scan Again
                                                                                    StopScan();
                                                                                    StartScan();
                                                                                  } });

    deviceWatcherStoppedToken = deviceWatcher.Stopped([this](DeviceWatcher sender, IInspectable args)
                                                      {
                                                        std::cout << "DeviceWatcherEvent: Stopped" << std::endl;
                                                        // DeviceWatcher Stopped
                                                      });
  }

  winrt::fire_and_forget UniversalBluetoothPlugin::ShowDevicePicker(std::function<void(std::optional<FlutterError> reply)> result)
  {
    DevicePicker picker = DevicePicker();
    picker.Filter().SupportedDeviceSelectors().Append(Bluetooth::BluetoothDevice::GetDeviceSelectorFromPairingState(false));
    auto selectedDevice = co_await picker.PickSingleDeviceAsync(Windows::Foundation::Rect(100, 100, 300, 300));
    if (selectedDevice == nullptr)
    {
      result(FlutterError("No device selected"));
      co_return;
    }

    std::function<void(ErrorOr<bool> reply)> pairCallback = [result](ErrorOr<bool> reply)
    {
      std::cout << "Received PairReply " << std::endl;
      if (reply.has_error() || !reply.value())
      {
        result(FlutterError("Pairing Failed"));
      }
      else
      {
        result(std::nullopt);
      }
    };

    auto address = ParseBluetoothClientId(selectedDevice.Id());
    std::cout << "Selected device " << address << " Pairing.." << std::endl;
    Pair(address, pairCallback);
  }

  winrt::fire_and_forget UniversalBluetoothPlugin::UnPairAsync(const std::string &address, std::function<void(std::optional<FlutterError> reply)> result)
  {
    try
    {
      auto device = co_await Bluetooth::BluetoothDevice::FromBluetoothAddressAsync(str_to_mac_address(address));
      if (device == nullptr)
      {
        result(FlutterError("Device not found"));
        co_return;
      }
      auto deviceInformation = device.DeviceInformation();
      bool isPaired = deviceInformation.Pairing().IsPaired();
      if (!isPaired)
      {
        result(FlutterError("Device is not paired"));
        co_return;
      }

      auto deviceUnpairingResult = async_get(deviceInformation.Pairing().UnpairAsync());
      auto unpairingStatus = deviceUnpairingResult.Status();
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::Failed)
      {
        result(FlutterError("Failed to unpair device"));
        co_return;
      }
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::AccessDenied)
      {
        result(FlutterError("Access denied"));
        co_return;
      }
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::AlreadyUnpaired)
      {
        result(FlutterError("Device is already unpaired"));
        co_return;
      }
      if (unpairingStatus == Enumeration::DeviceUnpairingResultStatus::OperationAlreadyInProgress)
      {
        result(FlutterError("OperationAlreadyInProgress"));
        co_return;
      }
      result(std::nullopt);
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "PairLog: Failed:  " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      result(FlutterError(std::to_string(errorCode), winrt::to_string(err.message())));
    }
    catch (...)
    {
      std::cout << "PairLog: Unknown error" << std::endl;
      result(FlutterError("Failed to unpair"));
    }
  }

  winrt::fire_and_forget UniversalBluetoothPlugin::PairAsync(const std::string &address, std::function<void(ErrorOr<bool> reply)> result)
  {
    try
    {
      auto device = co_await Bluetooth::BluetoothDevice::FromBluetoothAddressAsync(str_to_mac_address(address));
      if (device == nullptr)
      {
        result(FlutterError("Device not found"));
        co_return;
      }
      auto deviceInformation = device.DeviceInformation();
      if (deviceInformation.Pairing().IsPaired())
      {
        result(true);
      }
      else if (!deviceInformation.Pairing().CanPair())
      {
        result(FlutterError("Device is not pairable"));
      }
      else
      {
        auto pairResult = co_await deviceInformation.Pairing().PairAsync();
        std::cout << "PairLog: Received pairing status" << parsePairingResultStatus(pairResult.Status()) << std::endl;
        bool isPaired = pairResult.Status() == Enumeration::DevicePairingResultStatus::Paired;
        result(isPaired);
      }
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "PairLog: Failed:  " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      result(FlutterError(std::to_string(errorCode), winrt::to_string(err.message())));
    }
    catch (...)
    {
      result(false);
      std::cout << "PairLog: Unknown error" << std::endl;
    }
  }

  winrt::fire_and_forget UniversalBluetoothPlugin::CustomPairAsync(
      const std::string &address,
      std::function<void(ErrorOr<bool> reply)> result)
  {
    try
    {
      auto device = co_await Bluetooth::BluetoothDevice::FromBluetoothAddressAsync(str_to_mac_address(address));
      if (device == nullptr)
      {
        result(FlutterError("Device not found"));
        co_return;
      }
      auto deviceInformation = device.DeviceInformation();
      if (deviceInformation.Pairing().IsPaired())
        result(true);
      else if (!deviceInformation.Pairing().CanPair())
        result(FlutterError("Device is not pairable"));
      else
      {
        auto customPairing = deviceInformation.Pairing().Custom();
        winrt::event_token token = customPairing.PairingRequested({this, &UniversalBluetoothPlugin::PairingRequestedHandler});
        std::cout << "PairLog: Trying to pair" << std::endl;
        DevicePairingProtectionLevel protectionLevel = deviceInformation.Pairing().ProtectionLevel();
        // DevicePairingKinds => None, ConfirmOnly, DisplayPin, ProvidePin, ConfirmPinMatch, ProvidePasswordCredential
        auto pairResult = co_await customPairing.PairAsync(
            DevicePairingKinds::ConfirmOnly |
                DevicePairingKinds::DisplayPin |
                DevicePairingKinds::ProvidePin |
                DevicePairingKinds::ConfirmPinMatch,
            // | DevicePairingKinds::ProvidePasswordCredential,
            protectionLevel);
        std::cout << "PairLog: Got Pair Result" << std::endl;
        DevicePairingResultStatus status = pairResult.Status();
        customPairing.PairingRequested(token);
        std::cout << "PairLog: Received pairing status" << parsePairingResultStatus(pairResult.Status()) << std::endl;
        bool isPaired = status == Enumeration::DevicePairingResultStatus::Paired;
        result(isPaired);
      }
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "PairLog: Failed:  " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      result(FlutterError(std::to_string(errorCode), winrt::to_string(err.message())));
    }
    catch (...)
    {
      result(false);
      std::cout << "PairLog: Unknown error" << std::endl;
    }
  }

  void UniversalBluetoothPlugin::PairingRequestedHandler(DeviceInformationCustomPairing sender, DevicePairingRequestedEventArgs eventArgs)
  {
    std::cout << "PairLog: Got PairingRequest" << std::endl;
    DevicePairingKinds kind = eventArgs.PairingKind();
    if (kind == DevicePairingKinds::ProvidePin)
    {
      std::cout << "PairLog: Trying to get pin from user" << std::endl;
      hstring pin = askForPairingPin();
      std::wcout << "PairLog: Got Pin: " << pin.c_str() << std::endl;
      eventArgs.Accept(pin);
    }
    else
    {
      hstring pin = eventArgs.Pin();
      if (!pin.empty())
      {
        std::cout << "PairLog: Got pair request with pin: " << winrt::to_string(pin) << std::endl;
        bool confirmed = showPairConfirmationDialog(pin);
        if (confirmed)
        {
          std::cout << "PairLog: Pair Accepted by User" << std::endl;
          eventArgs.Accept(pin);
        }
        else
        {
          std::cout << "PairLog: Pair Rejected by User" << std::endl;
          // User rejected confirmation dialog, Ignore
        }
      }
      else
      {
        std::cout << "PairLog: Accepting pair without pin" << std::endl;
        eventArgs.Accept();
      }
    }
  }

  winrt::fire_and_forget UniversalBluetoothPlugin::DisconnectAsync(const std::string &device_id, std::function<void(std::optional<FlutterError> reply)> result)
  {
    try
    {
      Bluetooth::BluetoothDevice device = co_await Bluetooth::BluetoothDevice::FromBluetoothAddressAsync(str_to_mac_address(device_id));
      if (device != nullptr && device.ConnectionStatus() == BluetoothConnectionStatus::Connected)
      {
        device.Close();
        device = nullptr;
      }
      else
      {
        std::cout << "Device not connected" << std::endl;
      }
      result(std::nullopt);
    }
    catch (const winrt::hresult_error &err)
    {
      int errorCode = err.code();
      std::cout << "DisconnectAsync: " << winrt::to_string(err.message()) << " ErrorCode: " << std::to_string(errorCode) << std::endl;
      result(FlutterError(std::to_string(errorCode), winrt::to_string(err.message())));
    }
    catch (...)
    {
      std::cout << "DisconnectAsync: Unknown error" << std::endl;
      result(FlutterError("Something Went Wrong"));
    }
  }

  BluetoothDevice UniversalBluetoothPlugin::DeviceInfoToBluetoothDevice(DeviceInformation deviceInfo)
  {
    auto properties = deviceInfo.Properties();
    hstring address = deviceInfo.Id();
    if (properties.HasKey(deviceAddressKey))
    {
      auto bluetoothAddressPropertyValue = properties.Lookup(deviceAddressKey).as<IPropertyValue>();
      if (bluetoothAddressPropertyValue != nullptr)
      {
        address = bluetoothAddressPropertyValue.GetString();
      }
    }

    bool isPaired = deviceInfo.Pairing().IsPaired();
    if (properties.HasKey(isPairedKey))
    {
      auto isPairedPropertyValue = properties.Lookup(isPairedKey).as<IPropertyValue>();
      if (isPairedPropertyValue != nullptr)
      {
        isPaired = isPairedPropertyValue.GetBoolean();
      }
    }

    int64_t rssi = 0;
    if (properties.HasKey(signalStrengthKey))
    {
      auto rssiPropertyValue = properties.Lookup(signalStrengthKey).as<IPropertyValue>();
      if (rssiPropertyValue != nullptr)
      {
        rssi = rssiPropertyValue.GetInt64();
      }
    }

    auto deviceAddress = ParseBluetoothClientId(address);
    std::string name = winrt::to_string(deviceInfo.Name());
    bool *is_connected_with_hid = nullptr;
    DeviceClass *device_class = nullptr;
    DeviceType *device_type = nullptr;

    return BluetoothDevice(deviceAddress, &name, isPaired, is_connected_with_hid, rssi, device_class, device_type);
  }

} // namespace universal_bluetooth
