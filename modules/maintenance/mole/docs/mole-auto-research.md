# Mole automation research

## Conclusion

Mole does not provide built-in scheduled cleanup or automatic self-update.
Its documented interface exposes manual `mo clean` and `mo update` commands,
while the empty `mo` path only checks for updates and displays a notice.

The official feature request for scheduled cleanup via `launchd` is closed as
not planned: [Issue #544](https://github.com/tw93/Mole/issues/544).

## Sources

- [Mole README](https://github.com/tw93/Mole/blob/main/README.md)
- [Mole command dispatcher](https://github.com/tw93/Mole/blob/main/mole)
- [Mole update implementation](https://github.com/tw93/Mole/blob/main/lib/manage/update.sh)
- [Mole releases](https://github.com/tw93/Mole/releases)

The module automates the existing commands externally and does not copy Mole's
source code.
