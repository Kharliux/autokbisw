# Review notes

## Primary fix

The original implementation held `assignmentLock` while calling `TISSelectInputSource`. Because the distributed input-source notification is configured with `deliverImmediately`, macOS can invoke `onInputSourceChanged()` synchronously. That callback attempted to acquire the same non-recursive `NSLock`, which can freeze the service.

The updated implementation:

- updates `lastActiveKeyboard` before selecting the source;
- releases `assignmentLock` before calling Carbon or writing preferences;
- checks and logs the `OSStatus` returned by `TISSelectInputSource`;
- removes an unnecessary force unwrap when reading an input-source ID.

## Build/test limitation

This environment is Linux and does not provide the macOS-only Carbon and IOKit frameworks, so the package cannot be compiled here. Build and test it on macOS with full Xcode installed:

```sh
swift test
swift build --configuration release
```

## Suggested installation test

Run the patched binary in verbose mode first:

```sh
.build/release/autokbisw --verbose 2
```

Switch repeatedly between the Spanish and English keyboards. Confirm that the process stays responsive and that no `ERROR: Failed to select input source` message appears.
