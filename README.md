
# autokbisw

Automatic keyboard input source switching for macOS.

`autokbisw` automatically switches the macOS input source depending on the keyboard currently in use. It is designed for users who work with multiple physical keyboards using different layouts (for example, a built-in Latin American keyboard and an external Spanish ISO keyboard).

This repository is a **modernized fork** of the original project maintained by **ohueter**, with a focus on:

- Improved stability
- Better diagnostics
- Modern Swift/Xcode compatibility
- Long-term maintainability
- Enhanced physical keyboard management

---

# Features

- Automatic input source switching per keyboard
- Silent background service
- Homebrew integration
- Multiple keyboard support
- USB/Bluetooth identity linking
- Diagnostic tools for troubleshooting

---

# Installation

## Homebrew

```bash
brew tap ohueter/tap
brew install autokbisw
brew services start autokbisw
```

---

# Usage

List known keyboards:

```bash
autokbisw list
```

Verbose mode:

```bash
autokbisw --verbose 2
```

---

# Diagnostic commands (2.1)

```bash
autokbisw doctor
autokbisw link 2 3
autokbisw unlink 3
autokbisw assign 2 com.apple.keylayout.Spanish-ISO
autokbisw clear
```

## doctor

Runs a complete diagnostic of the current configuration.

Example:

```text
✓ Configuration store is readable
✓ Every known device has an input-source mapping
✓ Related keyboard identities are linked
✓ All known devices are enabled
```

## link

Links two HID identities that belong to the same physical keyboard (typically USB and Bluetooth) so they permanently share the same input-source configuration.

Example:

```bash
autokbisw link 2 3
```

---

# Troubleshooting

### The background service does not switch the input source

Reload the LaunchAgent:

```bash
launchctl unload ~/Library/LaunchAgents/homebrew.mxcl.autokbisw.plist
launchctl load ~/Library/LaunchAgents/homebrew.mxcl.autokbisw.plist
```

or restart the Homebrew service:

```bash
brew services restart autokbisw
```

---

# Roadmap

Current development focuses on:

- Improving HID diagnostics
- Better physical keyboard detection
- Modern Swift compatibility
- Improved logging
- Long-term maintenance

Future releases will continue improving reliability while remaining compatible with the original project.

---

# Changelog

See [CHANGELOG.md].

---

# Acknowledgements

The original implementation was created by **Jean Helou**.

The project was later maintained and significantly improved by **ohueter**.

This fork builds upon their excellent work while focusing on modernization, diagnostics and long-term maintenance.

Many thanks to both authors and to everyone who has contributed to the project.