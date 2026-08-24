# Adapters

Adapters describe environment-specific ways to install or run a module. They
are deliberately separate from capabilities:

- package managers: Homebrew, apt, dnf, apk;
- service managers: launchd, systemd, OpenRC;
- platforms: macOS, Linux, NAS, and Proxmox hosts.

The canonical command remains `homelab`. Homebrew integration is an optional
`brew homelab` adapter, not a requirement for modules to exist.
