# Modules

Modules are isolated units of homelab behavior. A module should own its
platform-specific scripts, templates, documentation, and validation.

Each module provides a `module.conf` manifest with an ID, optional aliases,
and a relative command entrypoint. The root CLI discovers manifests instead
of hard-coding a specific module.

Current modules:

- `maintenance/mole` — schedules Mole cleanup and updates with macOS launchd.

Future modules should be grouped by capability rather than by package manager
or operating system. Platform-specific details belong inside the module or in
an adapter.
