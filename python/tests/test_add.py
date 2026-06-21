import pytest

from wrangle_playground_fixture import add


def test_add_sums_values():
    assert add(1, 2, 3) == 6
    assert add() == 0
    assert add(-4, 4) == 0


def test_add_rejects_non_int():
    with pytest.raises(TypeError):
        add(1, "2")
    with pytest.raises(TypeError):
        add(True)
