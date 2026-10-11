# autokbisw

**Automatic keyboard input source switching for macOS.**

`autokbisw` remembers the input source (language or keyboard layout) you use with each physical keyboard and automatically restores it when you switch between keyboards.

For example, you can use Latin American on your MacBook's built-in keyboard, Spanish ISO on a Bluetooth keyboard, and U.S. on a USB keyboard—without manually changing the macOS input source each time.

It runs quietly in the background, with straightforward Terminal commands for setup and troubleshooting.

## Features

- Automatic input-source switching for individual physical keyboards
- Saved preferences across launches
- Built-in, USB, and Bluetooth keyboard support
- Optional linking of USB and Bluetooth identities for the **same** physical keyboard
- Diagnostics and device configuration commands
- Background service managed through Homebrew

## Installation

### Requirements

- A Mac running macOS
- [Homebrew](https://brew.sh)
- Apple's **Xcode Command Line Tools (CLT)** for building from source

**Full Xcode is not required to install autokbisw.** The Homebrew formula has been verified to build using the Command Line Tools alone. The development test suite uses XCTest and may require full Xcode; this does not affect installation.

### New to Homebrew or Terminal?

**Terminal** is an application included with macOS for entering commands. Open it using Spotlight: press **Command–Space**, type `Terminal`, and press Return.

**Homebrew** is a package manager that installs and maintains software using Terminal commands. If you do not have it yet:

1. Visit [brew.sh](https://brew.sh).
2. Copy the installation command displayed on the website.
3. Open Terminal.
4. Paste the command, press Return, and follow the instructions.

### Install and start autokbisw

Run these commands in Terminal:

```sh
brew install Kharliux/tap/autokbisw
brew services start Kharliux/tap/autokbisw
```

Homebrew compiles the application from source. If the Command Line Tools are missing, macOS may prompt you to install them. You can also request them manually with `xcode-select --install`.

**Input Monitoring permission:** macOS may ask you to allow autokbisw to monitor keyboard input. In **System Settings → Privacy & Security → Input Monitoring**, grant permission to the installed executable when prompted. This permission is needed to identify the physical keyboard in use. Restart the service if necessary after enabling it.

## Getting started

The first time you use a keyboard, autokbisw needs to learn which input source you prefer for it:

1. Type a few characters on the first keyboard to make it active.
2. Choose its preferred keyboard layout in the macOS input menu.
3. Type on the next keyboard, then choose the layout you want for that keyboard.
4. Repeat for any additional keyboards.

Afterwards, switching keyboards automatically restores their saved input sources. **The change occurs after keyboard activity is detected**, so the first keystroke when switching may still use the previous layout.

Check the saved devices and layouts with:

```sh
autokbisw list
```

## Commands

| Command | Purpose |
| --- | --- |
| `autokbisw list` | Show known keyboards and their assigned input sources |
| `autokbisw doctor` | Check stored configuration and identify possible issues |
| `autokbisw enable 2` | Enable automatic switching for device 2 |
| `autokbisw disable 2` | Disable automatic switching for device 2 |
| `autokbisw assign 2 com.apple.keylayout.Spanish-ISO` | Assign an installed macOS input source to device 2 |
| `autokbisw link 2 3` | Link two identities belonging to the **same physical keyboard** |
| `autokbisw unlink 3` | Remove an identity from its keyboard link |
| `autokbisw --help` | Display available commands and options |

Device numbers come from `autokbisw list`. Do not link different physical keyboards just because their product names are similar.

**Use caution with `autokbisw clear`:** it deletes stored device mappings and settings.

### Managing the background service

```sh
brew services list
brew services restart Kharliux/tap/autokbisw
brew services stop Kharliux/tap/autokbisw
brew services start Kharliux/tap/autokbisw
```

## Updating or uninstalling

To update to a newer version when one becomes available:

```sh
brew update
brew upgrade Kharliux/tap/autokbisw
brew services restart Kharliux/tap/autokbisw
```

To uninstall the application:

```sh
brew services stop Kharliux/tap/autokbisw
brew uninstall Kharliux/tap/autokbisw
```

## Troubleshooting

### The layout does not switch

Check the service with `brew services list` and the saved settings with `autokbisw doctor`. Verify **Input Monitoring** permission under **System Settings → Privacy & Security**. After granting or changing permission, restart the service:

```sh
brew services restart Kharliux/tap/autokbisw
```

Avoid manually loading or unloading a hard-coded LaunchAgent path: Homebrew's service label and file location can differ between versions.

### The installation reports missing developer tools

Run:

```sh
xcode-select --install
```

To inspect the selected developer directory:

```sh
xcode-select -p
```

A Command Line Tools installation commonly lives at `/Library/Developer/CommandLineTools`; full Xcode is not necessary for a Homebrew installation of autokbisw.

### A keyboard or mouse is identified incorrectly

Some HID devices report unexpected identifying information. Use `autokbisw list` and `autokbisw doctor` to inspect the device, then enable or disable automatic switching for the appropriate device if needed. See upstream issues [#7](https://github.com/ohueter/autokbisw/issues/7) and [#18](https://github.com/ohueter/autokbisw/issues/18).

### Input sources change unexpectedly

The macOS option **Automatically switch to a document's input source** may conflict with per-keyboard switching. See [upstream issue #33](https://github.com/ohueter/autokbisw/issues/33).

### Does it work with Karabiner-Elements?

Karabiner-Elements may proxy keyboard events in ways that prevent autokbisw from identifying the original device reliably. For an alternative approach, see this [Karabiner-Elements discussion](https://github.com/pqrs-org/Karabiner-Elements/issues/2230#issuecomment-2043513996).

## Building from source

Clone the repository, enter its directory, and run:

```sh
swift build --configuration release --disable-sandbox
```

The resulting executable is located at `.build/release/autokbisw`. A release build has been verified using Xcode Command Line Tools only. The project's current XCTest-based development suite may require full Xcode.

## About this fork

This is a modernized fork of autokbisw, focused on stability, diagnostics, long-term maintainability, and better physical-keyboard management.

### Acknowledgements

The original project was created by [Jean Helou](https://github.com/jeantil/autokbisw). It was later maintained and significantly improved by [Ole Hüter](https://github.com/ohueter/autokbisw).

This fork builds on their work, with thanks to both authors and the community.

Licensed under Apache-2.0.
