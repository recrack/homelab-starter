# Modules

Modules are isolated units of homelab behavior. A module should own its
platform-specific scripts, templates, documentation, and validation.

Each module provides a `module.conf` manifest with an ID, optional aliases,
and a relative command entrypoint. The root CLI discovers manifests instead
of hard-coding a specific module.

Current modules:

- `macos/mole-maintenance` — schedules Mole cleanup and updates with launchd.
