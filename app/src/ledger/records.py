"""Deterministic record generation.

The drill seeds data with a known seed so that any machine can predict the
exact dataset and its checksum. That makes restore verification objective.
"""

from __future__ import annotations

import hashlib
from collections.abc import Iterator


def generate(seed: str, start: int, count: int) -> Iterator[tuple[str, str]]:
    """Yield (key, value) pairs for records start..start+count-1."""
    if count < 0:
        raise ValueError("count must be non-negative")
    for i in range(start, start + count):
        key = f"{seed}-{i:08d}"
        value = hashlib.sha256(key.encode()).hexdigest()[:32]
        yield key, value


def checksum(rows: list[tuple[int, str, str]]) -> str:
    """Reference implementation of the checksum the database computes.

    Must stay byte-for-byte identical to CHECKSUM_SQL in db.py.
    """
    joined = ",".join(f"{rid}:{key}:{value}" for rid, key, value in sorted(rows))
    return hashlib.sha256(joined.encode()).hexdigest()
