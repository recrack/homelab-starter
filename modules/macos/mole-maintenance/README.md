# Mole maintenance module

This macOS module runs the existing Mole CLI from user LaunchAgents:

- `mo update` on the configured weekly schedule;
- `mo clean` one hour later on the same day;
- a shared lock prevents update and cleanup from overlapping;
- logs are stored under `~/Library/Logs/mole-auto-maintenance/`.

## Prerequisites

- macOS;
- Homebrew;
- `brew install mole`.

## Use through homelab-starter

From the repository root:

```sh
./bin/homelab module list
./bin/homelab module run mole --update-at 03:00 --cleanup-at 04:00 --day sunday
./bin/homelab status
./bin/homelab module run mole off
```

The module also exposes `scripts/mole-schedule.sh` for direct use. Its saved
schedule lives in `~/Library/Application Support/MoleAutoMaintenance/` and is
not part of the repository.

`mo clean` can delete files. Run `mo clean --dry-run` and configure
`mo clean --whitelist` before enabling automatic cleanup.

## Implementation

The module uses `launchd` templates under `launchd/` and installs a stable
runner under the user's Application Support directory. The templates contain
no machine-specific usernames or paths; `scripts/install-launchd.sh` fills
those values during installation.
