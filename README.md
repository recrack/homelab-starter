# homelab-starter

An opinionated, safe-by-default starting point for building a personal
homelab. Features are organized as optional modules so the same repository can
grow from a single Mac or mini server into a larger self-hosted setup.

## Current status

The first module is `maintenance/mole`. It schedules the existing Mole CLI for
cleanup and updates through macOS `launchd`.

`maintenance/container-reclaim` reports and reclaims sparse-image growth for
Apple `container` workloads, where blocks freed inside a container are never
returned to the host on their own.

This repository is under active development. Do not run automation modules on
important systems until you have reviewed their dry-run and recovery behavior.

## Quick start

```sh
./bin/homelab module list
./bin/homelab status
./bin/homelab module run mole --update-at 03:00 --cleanup-at 04:00 --day sunday
./bin/homelab module run mole --every-hour
./bin/homelab module run container-reclaim report
./bin/homelab module run container-reclaim doctor
```

The Mole module requires macOS, Homebrew, and the `mole` formula. To disable
its LaunchAgents:

```sh
./bin/homelab module run mole off
```

## Homebrew integration

`cmd/brew-homelab` is prepared as a Homebrew external-command entrypoint. A
future tap can expose the same interface as:

```sh
brew homelab status
brew homelab module run mole --update-at 03:00 --cleanup-at 04:00
brew homelab module run mole --every-hour
```

The canonical command remains `homelab` so future Linux, NAS, and Proxmox
modules do not depend on Homebrew.

## Repository layout

```text
bin/                         Root CLI
cmd/                         Homebrew external-command adapters
modules/                     Optional platform and service modules
profiles/                    Example machine profiles
docs/                        Project-wide documentation
```

## Safety

Modules may change local system state. Review each module's README, run its
dry-run mode where available, keep secrets out of Git, and make backups before
enabling destructive operations.

## License

The project-owned code is released under the MIT License. Third-party tools
such as Mole remain separately licensed by their respective authors.
