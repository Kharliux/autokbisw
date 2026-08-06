// Copyright 2016 Jean Helou
// Copyright 2024 Ole Hüter
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Carbon
import Foundation
import IOKit
import IOKit.hid
import IOKit.usb

public final class IOKeyEventMonitor {
    private let log: Logger

    private let hidManager: IOHIDManager
    fileprivate let notificationCenter: CFNotificationCenter

    fileprivate let MAPPINGS_DEFAULTS_KEY = "keyboardISMapping"
    fileprivate var defaults: UserDefaults = .standard

    fileprivate let MAPPING_ENABLED_KEY = "mappingEnabled"
    fileprivate let LINKED_DEVICES_KEY = "linkedDevices"
    var deviceEnabled: [String: Bool] = [:]
    var linkedDevices: [String: String] = [:]

    fileprivate let stateLock = NSLock()
    var lastActiveKeyboard: String?
    var kb2is: [String: TISInputSource] = .init()

    fileprivate var useLocation: Bool

    public init? (usagePage: Int, usage: Int, useLocation: Bool, verbosity: Int, userDefaults: UserDefaults = .standard) {
        self.useLocation = useLocation
        log = Logger(verbosity: verbosity)
        defaults = userDefaults

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        notificationCenter = CFNotificationCenterGetDistributedCenter()
        let deviceMatch: CFMutableDictionary = [kIOHIDDeviceUsageKey: usage, kIOHIDDeviceUsagePageKey: usagePage] as NSMutableDictionary
        IOHIDManagerSetDeviceMatching(hidManager, deviceMatch)

        loadMappings()
    }

    deinit {
        self.saveMappings()
        stopObservingSettingsChanges()

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(hidManager, Optional.none, context)
        CFNotificationCenterRemoveObserver(notificationCenter, context, CFNotificationName(kTISNotifySelectedKeyboardInputSourceChanged), nil)
    }

    public func start() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        observeIputSourceChangedNotification(context: context)
        registerHIDKeyboardCallback(context: context)

        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode!.rawValue)
        let openStatus = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openStatus != kIOReturnSuccess {
            log.error("Failed to open HID manager (IOReturn: \(openStatus)). Check Input Monitoring permissions.")
        } else {
            log.debug("HID manager started")
        }

        startObservingSettingsChanges()
    }

    private func observeIputSourceChangedNotification(context: UnsafeMutableRawPointer) {
        let inputSourceChanged: CFNotificationCallback = {
            _, observer, _, _, _ in
            guard let observer else { return }
            let selfPtr = Unmanaged<IOKeyEventMonitor>.fromOpaque(observer).takeUnretainedValue()
            selfPtr.onInputSourceChanged()
        }

        CFNotificationCenterAddObserver(notificationCenter,
                                        context, inputSourceChanged,
                                        kTISNotifySelectedKeyboardInputSourceChanged, nil,
                                        CFNotificationSuspensionBehavior.deliverImmediately)
    }

    private func registerHIDKeyboardCallback(context: UnsafeMutableRawPointer) {
        let myHIDKeyboardCallback: IOHIDValueCallback = {
            context, _, sender, _ in
            guard let context, let sender else { return }
            let selfPtr = Unmanaged<IOKeyEventMonitor>.fromOpaque(context).takeUnretainedValue()
            let senderDevice = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()

            let conformsToKeyboard = selfPtr.deviceConformsToKeyboard(senderDevice)

            let vendorId = selfPtr.deviceProperty(senderDevice, kIOHIDVendorIDKey)
            let productId = selfPtr.deviceProperty(senderDevice, kIOHIDProductIDKey)
            let product = selfPtr.deviceProperty(senderDevice, kIOHIDProductKey)
            let manufacturer = selfPtr.deviceProperty(senderDevice, kIOHIDManufacturerKey)
            let serialNumber = selfPtr.deviceProperty(senderDevice, kIOHIDSerialNumberKey)
            let locationId = selfPtr.deviceProperty(senderDevice, kIOHIDLocationIDKey)
            let uniqueId = selfPtr.deviceProperty(senderDevice, kIOHIDUniqueIDKey)
            let transport = selfPtr.deviceProperty(senderDevice, kIOHIDTransportKey)

            let isBuiltInKeyboard =
                product.lowercased().contains("internal keyboard") &&
                vendorId == "unknown" &&
                productId == "unknown"

            let keyboard: String

            if isBuiltInKeyboard {
                keyboard = "\(product)-[Apple-builtin]"
                selfPtr.migrateLegacyBuiltInKeyboardIdentity(
                    product: product,
                    to: keyboard
                )
            } else if selfPtr.useLocation {
                keyboard = "\(product)-[\(vendorId)-\(productId)-\(manufacturer)-\(serialNumber)-\(locationId)]"
            } else {
                keyboard = "\(product)-[\(vendorId)-\(productId)-\(manufacturer)-\(serialNumber)]"
            }

            selfPtr.log.trace("HID event: device=\(keyboard), transport=\(transport), vendor=\(vendorId), product=\(productId), location=\(locationId), unique=\(uniqueId), keyboard=\(conformsToKeyboard)")
            selfPtr.onKeyboardEvent(keyboard: keyboard, conformsToKeyboard: conformsToKeyboard)
        }

        IOHIDManagerRegisterInputValueCallback(hidManager, myHIDKeyboardCallback, context)
    }

    private func deviceProperty(_ device: IOHIDDevice, _ key: String) -> String {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return "unknown"
        }
        return String(describing: value)
    }

func migrateLegacyBuiltInKeyboardIdentity(
    product: String,
    to newKeyboard: String
) {
    let legacyPrefix = "\(product)-[unknown-unknown-"

    stateLock.lock()

    let knownKeyboards = Set(kb2is.keys)
        .union(deviceEnabled.keys)
        .union(linkedDevices.keys)

    let legacyKeyboards = knownKeyboards
        .filter {
            $0.hasPrefix(legacyPrefix) &&
                $0.hasSuffix("]")
        }
        .sorted()

    var migrated = false
    var foundConflict = false

    for legacyKeyboard in legacyKeyboards {
        let legacyInputSourceId =
            kb2is[legacyKeyboard].flatMap(is2Id)
        let newInputSourceId =
            kb2is[newKeyboard].flatMap(is2Id)

        let inputSourceConflicts =
            legacyInputSourceId != nil &&
            newInputSourceId != nil &&
            legacyInputSourceId != newInputSourceId

        let enabledConflicts =
            deviceEnabled[legacyKeyboard] != nil &&
            deviceEnabled[newKeyboard] != nil &&
            deviceEnabled[legacyKeyboard] != deviceEnabled[newKeyboard]

        let linkConflicts =
            linkedDevices[legacyKeyboard] != nil &&
            linkedDevices[newKeyboard] != nil &&
            linkedDevices[legacyKeyboard] != linkedDevices[newKeyboard]

        if inputSourceConflicts || enabledConflicts || linkConflicts {
            foundConflict = true
            continue
        }

        if kb2is[newKeyboard] == nil,
           let inputSource = kb2is[legacyKeyboard] {
            kb2is[newKeyboard] = inputSource
        }

        if deviceEnabled[newKeyboard] == nil,
           let enabled = deviceEnabled[legacyKeyboard] {
            deviceEnabled[newKeyboard] = enabled
        }

        if linkedDevices[newKeyboard] == nil,
           let group = linkedDevices[legacyKeyboard] {
            linkedDevices[newKeyboard] = group
        }

        kb2is.removeValue(forKey: legacyKeyboard)
        deviceEnabled.removeValue(forKey: legacyKeyboard)
        linkedDevices.removeValue(forKey: legacyKeyboard)
        migrated = true
    }

    stateLock.unlock()

    if migrated {
        log.debug(
            "Migrated legacy built-in keyboard identity to \(newKeyboard)"
        )
        saveMappings()
    }

    if foundConflict {
        log.debug(
            "Preserved conflicting legacy and stable built-in keyboard settings"
        )
    }
}






    private func deviceConformsToKeyboard(_ device: IOHIDDevice) -> Bool {
        return IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard))
    }
}

// MARK: - Input Source Management

public extension IOKeyEventMonitor {
    func restoreInputSource(keyboard: String) {
        stateLock.lock()
        let targetIs = kb2is[keyboard]
        stateLock.unlock()

        guard let targetIs else {
            log.trace("No previous mapping saved for \(keyboard), awaiting the user to select the right one")
            return
        }

        log.debug("Setting input source for keyboard \(keyboard): \(targetIs)")

        // This can synchronously trigger onInputSourceChanged(). Never call it
        // while stateLock is held, otherwise the callback can deadlock.
        let status = TISSelectInputSource(targetIs)
        if status != noErr {
            log.error("Failed to select input source for keyboard \(keyboard) (OSStatus: \(status))")
        }
    }

    func storeInputSource(keyboard: String, conformsToKeyboard: Bool? = nil) {
        let currentSource: TISInputSource = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()

        stateLock.lock()
        kb2is[keyboard] = currentSource

        // Linked identities represent the same physical keyboard. Teaching one
        // member updates every linked USB/Bluetooth identity.
        if let group = linkedDevices[keyboard] {
            let members = linkedDevices.filter { $0.value == group }.map { $0.key }
            for member in members {
                kb2is[member] = currentSource
            }
        }

        // Only set a default value for deviceEnabled if conformsToKeyboard is provided.
        if let isKeyboard = conformsToKeyboard, deviceEnabled[keyboard] == nil {
            log.debug("Setting initial device state to \(isKeyboard ? "enabled" : "disabled")")
            deviceEnabled[keyboard] = isKeyboard
        }
        stateLock.unlock()

        log.trace("Stored input source \(is2Id(currentSource) ?? "unknown") for \(keyboard)")
        saveMappings()
    }

    func onInputSourceChanged() {
        // Copy the active keyboard while holding the lock, then release it before
        // reading Carbon state or writing UserDefaults. TISSelectInputSource may
        // deliver this notification synchronously.
        stateLock.lock()
        let keyboard = lastActiveKeyboard
        stateLock.unlock()

        // lastActiveKeyboard can be nil only if the language is changed between
        // program start and the first keypress, so we can ignore this edge case.
        if let keyboard {
            storeInputSource(keyboard: keyboard)
        }
    }

    func onKeyboardEvent(keyboard: String, conformsToKeyboard: Bool? = nil) {
        // Update the active keyboard before selecting its input source. If Carbon
        // immediately sends an input-source-changed notification, that callback
        // must associate the selected source with the new keyboard, not the old one.
        stateLock.lock()

        guard lastActiveKeyboard != keyboard else {
            stateLock.unlock()
            log.trace("change: ignoring event from keyboard \(keyboard) because active device hasn't changed")
            return
        }

        let previousKeyboard = lastActiveKeyboard
        let isEnabled = deviceEnabled[keyboard] ?? true
        guard isEnabled else {
            stateLock.unlock()
            log.trace("change: ignoring event from keyboard \(keyboard) because device is disabled")
            return
        }

        let hasStoredMapping = kb2is[keyboard] != nil
        lastActiveKeyboard = keyboard
        stateLock.unlock()

        log.debug("change: keyboard changed from \(previousKeyboard ?? "nil") to \(keyboard)")

        // Do not hold stateLock across either operation. In particular,
        // restoreInputSource() calls TISSelectInputSource(), which can synchronously
        // invoke onInputSourceChanged().
        if hasStoredMapping {
            restoreInputSource(keyboard: keyboard)
        } else {
            log.debug("New device detected: \(keyboard), storing current input source")
            storeInputSource(keyboard: keyboard, conformsToKeyboard: conformsToKeyboard)
        }
    }
}

// MARK: - Device Management

public extension IOKeyEventMonitor {
    func enableDevice(_ keyboard: String) {
        stateLock.lock()
        deviceEnabled[keyboard] = true
        stateLock.unlock()
        saveMappings()
    }

    func disableDevice(_ keyboard: String) {
        stateLock.lock()
        deviceEnabled[keyboard] = false
        stateLock.unlock()
        saveMappings()
    }

    func enableDeviceByNumber(_ number: Int) {
        stateLock.lock()
        let devices = Array(deviceEnabled.keys).sorted()
        stateLock.unlock()
        guard number > 0, number <= devices.count else {
            print("Invalid device number")
            return
        }
        let keyboard = devices[number - 1]
        stateLock.lock()
        deviceEnabled[keyboard] = true
        stateLock.unlock()
        saveMappings()
    }

    func disableDeviceByNumber(_ number: Int) {
        stateLock.lock()
        let devices = Array(deviceEnabled.keys).sorted()
        stateLock.unlock()
        guard number > 0, number <= devices.count else {
            print("Invalid device number")
            return
        }
        let keyboard = devices[number - 1]
        stateLock.lock()
        deviceEnabled[keyboard] = false
        stateLock.unlock()
        saveMappings()
    }

    @discardableResult
    func copyInputSource(fromNumber sourceNumber: Int, toNumber destinationNumber: Int) -> Bool {
        stateLock.lock()
        let devices = Array(deviceEnabled.keys).sorted()

        guard sourceNumber > 0, sourceNumber <= devices.count,
              destinationNumber > 0, destinationNumber <= devices.count,
              sourceNumber != destinationNumber else {
            stateLock.unlock()
            return false
        }

        let sourceKeyboard = devices[sourceNumber - 1]
        let destinationKeyboard = devices[destinationNumber - 1]

        guard let sourceInputSource = kb2is[sourceKeyboard] else {
            stateLock.unlock()
            return false
        }

        kb2is[destinationKeyboard] = sourceInputSource
        deviceEnabled[destinationKeyboard] = deviceEnabled[sourceKeyboard] ?? true
        stateLock.unlock()

        saveMappings()
        log.debug("Copied input source from device #\(sourceNumber) to device #\(destinationNumber)")
        return true
    }

    @discardableResult
    func linkDevices(_ firstNumber: Int, _ secondNumber: Int) -> Bool {
        stateLock.lock()
        let devices = Array(deviceEnabled.keys).sorted()
        guard firstNumber > 0, firstNumber <= devices.count,
              secondNumber > 0, secondNumber <= devices.count,
              firstNumber != secondNumber else {
            stateLock.unlock()
            return false
        }

        let first = devices[firstNumber - 1]
        let second = devices[secondNumber - 1]
        let group = linkedDevices[first] ?? linkedDevices[second] ?? UUID().uuidString
        linkedDevices[first] = group
        linkedDevices[second] = group

        // Prefer the first device's mapping, then the second's. Linking is explicit,
        // so synchronizing immediately is less surprising than waiting for a keypress.
        if let source = kb2is[first] ?? kb2is[second] {
            kb2is[first] = source
            kb2is[second] = source
        }
        let enabled = deviceEnabled[first] ?? deviceEnabled[second] ?? true
        deviceEnabled[first] = enabled
        deviceEnabled[second] = enabled
        stateLock.unlock()

        saveMappings()
        return true
    }

    @discardableResult
    func unlinkDevice(_ number: Int) -> Bool {
        stateLock.lock()
        let devices = Array(deviceEnabled.keys).sorted()
        guard number > 0, number <= devices.count else {
            stateLock.unlock()
            return false
        }
        let keyboard = devices[number - 1]
        linkedDevices.removeValue(forKey: keyboard)
        stateLock.unlock()
        saveMappings()
        return true
    }

    @discardableResult
    func assignInputSource(deviceNumber: Int, inputSourceId: String) -> Bool {
        let properties = [kTISPropertyInputSourceID: inputSourceId as CFString] as CFDictionary
        let matches = TISCreateInputSourceList(properties, false).takeUnretainedValue() as! [TISInputSource]
        guard let source = matches.first else { return false }

        stateLock.lock()
        let devices = Array(deviceEnabled.keys).sorted()
        guard deviceNumber > 0, deviceNumber <= devices.count else {
            stateLock.unlock()
            return false
        }
        let keyboard = devices[deviceNumber - 1]
        kb2is[keyboard] = source
        if let group = linkedDevices[keyboard] {
            let members = linkedDevices.filter { $0.value == group }.map { $0.key }
            for member in members {
                kb2is[member] = source
            }
        }
        stateLock.unlock()
        saveMappings()
        return true
    }

    func getDoctorReport() -> String {
        stateLock.lock()
        let enabledSnapshot = deviceEnabled
        let mappingsSnapshot = kb2is
        let linksSnapshot = linkedDevices
        stateLock.unlock()

        var lines: [String] = []
        lines.append("autokbisw doctor")
        lines.append("✓ Configuration store is readable")
        lines.append("✓ \(enabledSnapshot.count) known device(s)")

        let missingMappings = enabledSnapshot.keys.filter { mappingsSnapshot[$0] == nil }
        if missingMappings.isEmpty {
            lines.append("✓ Every known device has an input-source mapping")
        } else {
            lines.append("⚠ \(missingMappings.count) device(s) have no input-source mapping")
        }

        let disabledCount = enabledSnapshot.values.filter { !$0 }.count
        if disabledCount == 0 {
            lines.append("✓ All known devices are enabled")
        } else {
            lines.append("ℹ \(disabledCount) device(s) are disabled")
        }

        let numberedDevices = enabledSnapshot.keys.sorted()
        let magicKeyboards = numberedDevices.enumerated().filter { _, keyboard in
            keyboard.lowercased().contains("magic keyboard")
        }
        if magicKeyboards.count > 1 {
            let unlinked = magicKeyboards.filter { _, keyboard in linksSnapshot[keyboard] == nil }
            if unlinked.count > 1 {
                let numbers = unlinked.map { String($0.offset + 1) }.joined(separator: ", ")
                lines.append("ℹ Multiple Apple Magic Keyboard identities detected (#\(numbers)). If they are USB/Bluetooth modes of one keyboard, run 'autokbisw link <number> <number>'.")
            } else {
                lines.append("✓ Related Magic Keyboard identities are linked")
            }
        } else {
            lines.append("✓ No likely USB/Bluetooth duplicate devices detected")
        }

        let groups = Dictionary(grouping: linksSnapshot.keys) { linksSnapshot[$0] ?? "" }.filter { !$0.key.isEmpty }
        if !groups.isEmpty {
            lines.append("✓ \(groups.count) linked physical-keyboard group(s)")
        }

        lines.append("ℹ Input Monitoring permission can only be verified while the service is running and receiving HID events")
        return lines.joined(separator: "\n")
    }

    func getDevicesString() -> String {
        stateLock.lock()
        let enabledSnapshot = deviceEnabled
        let mappingsSnapshot = kb2is
        let linksSnapshot = linkedDevices
        stateLock.unlock()

        return enabledSnapshot
            .sorted { $0.key < $1.key }
            .enumerated()
            .map { index, entry -> String in
                let (keyboard, isEnabled) = entry
                let number = index + 1
                let status = isEnabled ? "enabled" : "disabled"
                var layoutInfo = "no layout stored"

                if let source = mappingsSnapshot[keyboard] {
                    let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
                    let localizedName = unmanagedStringToString(name) ?? "unknown"
                    let id = is2Id(source) ?? "unknown"
                    layoutInfo = "\(localizedName) (\(id))"
                }

                let linked = linksSnapshot[keyboard].map { " - linked[\($0.prefix(8))]" } ?? ""
                return "\(number). \(keyboard): \(status) - \(layoutInfo)\(linked)"
            }
            .joined(separator: "\n")
    }
}

// MARK: - Persistence

extension IOKeyEventMonitor {
    func loadMappings() {
        var loadedMappings: [String: TISInputSource] = [:]
        var loadedEnabled: [String: Bool] = [:]
        var loadedLinks: [String: String] = [:]

        let selectableIsProperties = [
            kTISPropertyInputSourceIsEnableCapable: true,
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource ?? "" as CFString,
        ] as CFDictionary
        let inputSources = TISCreateInputSourceList(selectableIsProperties, false).takeUnretainedValue() as! [TISInputSource]

        let inputSourcesById = inputSources.reduce([String: TISInputSource]()) {
            dict, inputSource -> [String: TISInputSource] in
            var dict = dict
            if let id = unmanagedStringToString(TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)) {
                dict[id] = inputSource
            }
            return dict
        }

        if let mappings = defaults.dictionary(forKey: MAPPINGS_DEFAULTS_KEY) {
            for (keyboardId, inputSourceId) in mappings {
                loadedMappings[keyboardId] = inputSourcesById[String(describing: inputSourceId)]
            }
        }

        if let enabledMappings = defaults.dictionary(forKey: MAPPING_ENABLED_KEY) as? [String: Bool] {
            loadedEnabled = enabledMappings
        }
        if let links = defaults.dictionary(forKey: LINKED_DEVICES_KEY) as? [String: String] {
            loadedLinks = links
        }

        stateLock.lock()
        kb2is = loadedMappings
        deviceEnabled = loadedEnabled
        linkedDevices = loadedLinks
        stateLock.unlock()
    }

    func saveMappings() {
        stateLock.lock()
        let mappings = kb2is.mapValues(is2Id)
        let enabledSnapshot = deviceEnabled
        let linksSnapshot = linkedDevices
        stateLock.unlock()

        withPausedSettingsObserver {
            defaults.set(mappings, forKey: MAPPINGS_DEFAULTS_KEY)
            defaults.set(enabledSnapshot, forKey: MAPPING_ENABLED_KEY)
            defaults.set(linksSnapshot, forKey: LINKED_DEVICES_KEY)
            defaults.synchronize()

            postSettingsChangedNotification()
        }

        log.trace("Saved keyboard mappings to UserDefaults")
    }

    public func clearAllSettings() {
        withPausedSettingsObserver {
            stateLock.lock()
            kb2is.removeAll()
            deviceEnabled.removeAll()
            linkedDevices.removeAll()
            lastActiveKeyboard = nil
            stateLock.unlock()
            defaults.removeObject(forKey: MAPPINGS_DEFAULTS_KEY)
            defaults.removeObject(forKey: MAPPING_ENABLED_KEY)
            defaults.removeObject(forKey: LINKED_DEVICES_KEY)
            defaults.synchronize()

            postSettingsChangedNotification()
        }
    }
}

// MARK: - Settings Change Notifications

private extension IOKeyEventMonitor {
    private func startObservingSettingsChanges() {
        log.trace("Starting UserDefaults observation")

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: CFNotificationCallback = { _, observer, _, _, _ in
            guard let observer else { return }
            let selfPtr = Unmanaged<IOKeyEventMonitor>.fromOpaque(observer).takeUnretainedValue()
            selfPtr.log.trace("Received settings change notification")
            selfPtr.onSettingsChanged()
        }

        CFNotificationCenterAddObserver(
            notificationCenter,
            context,
            callback,
            "com.autokbisw.settingsChanged" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func stopObservingSettingsChanges() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterRemoveObserver(
            notificationCenter,
            context,
            CFNotificationName("com.autokbisw.settingsChanged" as CFString),
            nil
        )
    }

    private func postSettingsChangedNotification() {
        log.trace("Posting settings changed notification")
        CFNotificationCenterPostNotification(
            notificationCenter,
            CFNotificationName("com.autokbisw.settingsChanged" as CFString),
            nil,
            nil,
            true
        )
    }

    private func withPausedSettingsObserver<T>(_ operation: () -> T) -> T {
        stopObservingSettingsChanges()
        defer { startObservingSettingsChanges() }
        return operation()
    }

    private func onSettingsChanged() {
        loadMappings()

        // If mappings are empty, settings were cleared in another instance.
        stateLock.lock()
        if kb2is.isEmpty, deviceEnabled.isEmpty {
            lastActiveKeyboard = nil
        }
        stateLock.unlock()

        log.trace("Reloaded mappings due to UserDefaults change")
    }
}

// MARK: - Utilities

extension IOKeyEventMonitor {
    private func is2Id(_ inputSource: TISInputSource) -> String? {
        return unmanagedStringToString(
            TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
        )
    }

    func unmanagedStringToString(_ p: UnsafeMutableRawPointer?) -> String? {
        if let cfValue = p {
            let value = Unmanaged.fromOpaque(cfValue).takeUnretainedValue() as CFString
            if CFGetTypeID(value) == CFStringGetTypeID() {
                return value as String
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
