# autokbisw 2.1.0-alpha2

Built on alpha1 after confirming automatic switching works between the internal keyboard and Magic Keyboard.

## Added

- `autokbisw copy <source> <destination>` copies the stored input source and enabled state between numbered devices.
- `autokbisw doctor` checks saved mappings, disabled devices, and likely duplicate USB/Bluetooth identities.
- Three tests for copy validation and duplicate-device diagnosis.

## Deliberately deferred

Automatic USB/Bluetooth merging remains opt-in. Device names and identifiers supplied by macOS are not reliable enough to merge identities silently without risking unrelated keyboards.
