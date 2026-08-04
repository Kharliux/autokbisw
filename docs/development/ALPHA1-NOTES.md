# autokbisw 2.1.0-alpha1

This alpha is based on the locally fixed version that passed the original 14 tests.

Changes:
- Avoids holding the state lock while calling `TISSelectInputSource`.
- Synchronizes mapping, enabled-device, and active-keyboard state access.
- Makes HID and distributed-notification callbacks tolerate missing callback pointers.
- Reports failure to open the HID manager (usually an Input Monitoring permission issue).
- Adds richer TRACE output with transport, vendor/product, location, and unique IDs.
- Keeps the existing UserDefaults keys and keyboard identifiers, so current mappings remain compatible.

This alpha deliberately does not merge USB and Bluetooth identities automatically.
