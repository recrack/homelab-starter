# Mole maintenance module

This macOS module runs the existing Mole CLI from user LaunchAgents:

- `mo update` on the configured weekly schedule;
- `mo clean` one hour later on the same day;
- optional hourly `mo clean` mode;
- a shared lock prevents update and cleanup from overlapping;
- logs are stored under `~/Library/Logs/mole-auto-maintenance/` when space is
  available; a full disk does not prevent the runner from starting.

## Prerequisites

- macOS;
- Homebrew;
- `brew install mole`.

## Use through homelab-starter

From the repository root:

```sh
./bin/homelab module list
./bin/homelab module run mole --update-at 03:00 --cleanup-at 04:00 --day sunday
./bin/homelab module run mole --every-hour
./bin/homelab status
./bin/homelab module run mole off
```

The module also exposes `scripts/mole-schedule.sh` for direct use. Its saved
schedule lives in `~/Library/Application Support/MoleAutoMaintenance/` and is
not part of the repository.

`mo clean` can delete files. Run `mo clean --dry-run` and configure
`mo clean --whitelist` before enabling automatic cleanup.

`--every-hour` affects cleanup only. The weekly `mo update` job remains
separate, and system-level cleanup that requires sudo is skipped in the
non-interactive LaunchAgent rather than prompting for a password.

## Implementation

The module uses `launchd` templates under `launchd/` and installs a stable
runner under the user's Application Support directory. The templates contain
no machine-specific usernames or paths; `scripts/install-launchd.sh` fills
those values during installation.
