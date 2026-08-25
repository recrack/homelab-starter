# maintenance/container-reclaim

Reports and reclaims sparse-image growth for Apple `container` workloads on
macOS.

## The problem

Apple `container` backs each container with a sparse ext4 image, typically
512 GiB nominal. The host allocates blocks as the guest writes them, but when
the guest frees a file the blocks are **not** returned to the host. Host usage
therefore only ever grows, even when the container's real contents are stable.

A long-running container that repeatedly writes and deletes temporary files —
a headless browser rewriting its profile on every run is the usual case —
can hold tens of gigabytes of blocks the guest has already freed.

`fstrim` inside the guest returns those blocks. The catch is timing:

> Once the host volume is full, `container exec` stops responding. `fstrim`
> runs through `exec`. The only tool that can free the space needs the space
> that is missing.

At that point the guest also starts logging `I/O error ... op WRITE` and
`EXT4-fs: failed to convert unwritten extents ... potential data loss`,
because the sparse file can no longer grow.

This module exists to keep the host out of that deadlock.

## Usage

```sh
./bin/homelab module run container-reclaim report
./bin/homelab module run container-reclaim doctor
./bin/homelab module run container-reclaim trim
```

### report

Compares guest usage against host allocation for every container image,
reading only the ext4 superblock. It never mounts the image, so it works even
while `container exec` is unresponsive.

```text
Free space on container volume: 42 GiB

.../containers/crawler/rootfs.ext4
  nominal (sparse) :    512.0 GiB
  guest used       :     10.4 GiB
  host allocated   :     36.5 GiB
  reclaimable      :     26.1 GiB  (fstrim)
  inodes used      : 36,377
```

`reclaimable` is the gap between what the guest actually uses and what the
host has handed out. A container storing its data compressed can report
`host allocated` *below* `guest used`; that is normal and yields `0.0`.

### doctor

Checks the two conditions that make the problem unrecoverable: free space
below `MIN_FREE_GIB`, and an unresponsive `container exec`. Exits non-zero if
either holds.

### trim

Runs `fstrim` in each idle container. A container is skipped when its
`/health` endpoint reports work in flight, and when idle state cannot be
determined at all. Use `--force NAME` to override the second case.

Every `container exec` is bounded by `EXEC_TIMEOUT` (default 60s), so a wedged
host produces a failure rather than a job that hangs forever.

## Scheduling

```sh
./modules/maintenance/container-reclaim/scripts/install-launchd.sh
./modules/maintenance/container-reclaim/scripts/uninstall-launchd.sh
```

Installs a LaunchAgent that trims daily at 04:30, logging to
`~/Library/Logs/container-reclaim.log`.

Scheduling is the point of the module. A trim script that exists but is only
ever run by hand will not be run on the day it is needed — by then `exec` is
already blocked.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `CONTAINER_CLI` | `/usr/local/bin/container` | Path to the container binary |
| `CONTAINER_ROOT` | `~/Library/Application Support/com.apple.container` | Container data root |
| `EXEC_TIMEOUT` | `60` | Seconds before a container exec is abandoned |
| `MIN_FREE_GIB` | `5` | Free-space floor for `doctor` |

## Recovering an already-full host

`trim` cannot help once `exec` is wedged. Free space by other means first:

1. Delete the build cache — `container builder delete`, recreated on next
   build by `container builder start`.
2. Remove unused images and their snapshots.
3. Clear host-side caches unrelated to the container runtime.

Then run `doctor` until `exec` is responsive again, and `trim` to reclaim the
rest. Recreating a container also returns the space, but discards anything
written inside it that is not on a mounted volume.

## Notes

Containers that write nothing but their own data — and whose data is pushed
elsewhere — are still worth trimming, because the growth comes from temporary
files, not from the data you meant to keep.

If a container holds state you care about, put it on a mounted volume. Volumes
live on the host filesystem and are not subject to this behavior at all.
