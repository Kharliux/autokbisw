# autokbisw 2.1.0-beta1

Beta 1 builds on Alpha 2 and adds explicit physical-keyboard links for silent/background operation.

## New commands

- `autokbisw link 2 3`: links two stored identities (for example Bluetooth and USB modes of the same keyboard). Teaching either identity updates both.
- `autokbisw unlink 3`: removes one identity from its link.
- `autokbisw assign 2 com.apple.keylayout.Spanish-ISO`: assigns an installed input source without the manual learning cycle.
- `autokbisw doctor`: suggests linking when multiple Magic Keyboard identities are present.
- `autokbisw clear`: now also removes link metadata, enabling a truly clean first-run test.

## Compatibility

Existing Alpha 2 mappings remain valid. Links are additional metadata and are only created by the explicit `link` command.
