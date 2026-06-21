"""Disposable fixture for e2e-testing wrangle's Python build workflow.

The function below exists only so the package has real behavior for the
unit test in ``tests/`` to exercise — wrangle's Python build runs
``pytest`` before packaging the wheel/sdist.
"""

__version__ = "0.0.1"


def add(*values: int) -> int:
    """Return the sum of ``values``, rejecting non-int (and bool) inputs."""
    for value in values:
        if not isinstance(value, int) or isinstance(value, bool):
            raise TypeError(f"add() expects int values, got {value!r}")
    return sum(values)
