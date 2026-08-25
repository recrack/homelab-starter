#!/usr/bin/env python3
"""Report guest-used vs host-allocated bytes for a sparse ext4 disk image.

Apple `container` backs each container with a sparse ext4 image (commonly
512 GiB nominal). Blocks the guest frees are not returned to the host
automatically, so the host allocation only ever grows. Comparing the ext4
superblock against the host allocation reveals how much is reclaimable by
`fstrim` without reading the filesystem contents.

Reads only the 1 KiB superblock; never mounts or modifies the image.
"""

from __future__ import annotations

import argparse
import json
import os
import struct
import sys

SUPERBLOCK_OFFSET = 1024
SUPERBLOCK_SIZE = 1024
EXT4_MAGIC = 0xEF53

# Offsets within the superblock (ext4 on-disk layout).
OFF_INODES_COUNT = 0x00
OFF_BLOCKS_COUNT_LO = 0x04
OFF_FREE_BLOCKS_LO = 0x0C
OFF_FREE_INODES = 0x10
OFF_LOG_BLOCK_SIZE = 0x18
OFF_MAGIC = 0x38
OFF_BLOCKS_COUNT_HI = 0x150
OFF_FREE_BLOCKS_HI = 0x158


def read_superblock(path: str) -> dict[str, int]:
    with open(path, "rb") as handle:
        handle.seek(SUPERBLOCK_OFFSET)
        sb = handle.read(SUPERBLOCK_SIZE)

    if len(sb) < SUPERBLOCK_SIZE:
        raise ValueError(f"short read on superblock: {path}")

    (magic,) = struct.unpack_from("<H", sb, OFF_MAGIC)
    if magic != EXT4_MAGIC:
        raise ValueError(f"not an ext2/3/4 image (magic {magic:#06x}): {path}")

    (log_block_size,) = struct.unpack_from("<I", sb, OFF_LOG_BLOCK_SIZE)
    block_size = 1024 << log_block_size

    (blocks_lo,) = struct.unpack_from("<I", sb, OFF_BLOCKS_COUNT_LO)
    (blocks_hi,) = struct.unpack_from("<I", sb, OFF_BLOCKS_COUNT_HI)
    (free_lo,) = struct.unpack_from("<I", sb, OFF_FREE_BLOCKS_LO)
    (free_hi,) = struct.unpack_from("<I", sb, OFF_FREE_BLOCKS_HI)

    total_blocks = (blocks_hi << 32) | blocks_lo
    free_blocks = (free_hi << 32) | free_lo

    (inodes_total,) = struct.unpack_from("<I", sb, OFF_INODES_COUNT)
    (inodes_free,) = struct.unpack_from("<I", sb, OFF_FREE_INODES)

    return {
        "block_size": block_size,
        "total_bytes": total_blocks * block_size,
        "free_bytes": free_blocks * block_size,
        "used_bytes": (total_blocks - free_blocks) * block_size,
        "inodes_used": inodes_total - inodes_free,
    }


def host_allocated_bytes(path: str) -> int:
    """Bytes actually occupied on the host, not the sparse apparent size."""
    return os.stat(path).st_blocks * 512


def gib(value: int) -> float:
    return value / (1 << 30)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare guest ext4 usage against host allocation."
    )
    parser.add_argument("image", nargs="+", help="path to a sparse ext4 image")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    args = parser.parse_args()

    reports = []
    exit_code = 0

    for image in args.image:
        try:
            info = read_superblock(image)
            allocated = host_allocated_bytes(image)
        except (OSError, ValueError) as error:
            print(f"error: {image}: {error}", file=sys.stderr)
            exit_code = 1
            continue

        # Blocks the guest has freed but the host has not taken back.
        reclaimable = max(0, allocated - info["used_bytes"])
        reports.append(
            {
                "image": image,
                "guest_used_bytes": info["used_bytes"],
                "host_allocated_bytes": allocated,
                "reclaimable_bytes": reclaimable,
                "nominal_bytes": info["total_bytes"],
                "inodes_used": info["inodes_used"],
            }
        )

    if args.json:
        print(json.dumps(reports, indent=2))
        return exit_code

    for report in reports:
        print(f"{report['image']}")
        print(f"  nominal (sparse) : {gib(report['nominal_bytes']):8.1f} GiB")
        print(f"  guest used       : {gib(report['guest_used_bytes']):8.1f} GiB")
        print(f"  host allocated   : {gib(report['host_allocated_bytes']):8.1f} GiB")
        print(f"  reclaimable      : {gib(report['reclaimable_bytes']):8.1f} GiB  (fstrim)")
        print(f"  inodes used      : {report['inodes_used']:,}")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
