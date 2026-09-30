from ledger import records


def test_generate_is_deterministic():
    assert list(records.generate("s", 0, 3)) == list(records.generate("s", 0, 3))


def test_generate_ranges_do_not_overlap():
    first = {k for k, _ in records.generate("s", 0, 100)}
    second = {k for k, _ in records.generate("s", 100, 100)}
    assert first.isdisjoint(second)


def test_generate_rejects_negative_count():
    import pytest

    with pytest.raises(ValueError):
        list(records.generate("s", 0, -1))


def test_checksum_is_order_independent():
    rows = [(2, "b", "y"), (1, "a", "x")]
    assert records.checksum(rows) == records.checksum(list(reversed(rows)))


def test_checksum_detects_single_change():
    rows = [(1, "a", "x"), (2, "b", "y")]
    changed = [(1, "a", "x"), (2, "b", "z")]
    assert records.checksum(rows) != records.checksum(changed)
