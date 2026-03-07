"""
theme_preview.py — Python syntax showcase
Covers: imports, classes, decorators, types, comprehensions,
        generators, async/await, exceptions, f-strings, dunders
"""

from __future__ import annotations

import asyncio
import math
import re
from dataclasses import dataclass, field
from enum import Enum, auto
from functools import wraps
from typing import Any, Callable, Generator, Generic, Optional, TypeVar

T = TypeVar("T")

# ── Constants ──────────────────────────────────────────────────────────────────
MAX_RETRIES: int = 3
PI: float = math.pi
PATTERN: re.Pattern = re.compile(r"^[a-z_]\w*$", re.IGNORECASE)


# ── Enum ───────────────────────────────────────────────────────────────────────
class Status(Enum):
    PENDING  = auto()
    RUNNING  = auto()
    COMPLETE = auto()
    FAILED   = auto()


# ── Decorator ─────────────────────────────────────────────────────────────────
def retry(times: int = MAX_RETRIES) -> Callable:
    """Retry decorator with configurable attempts."""
    def decorator(fn: Callable) -> Callable:
        @wraps(fn)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            for attempt in range(1, times + 1):
                try:
                    return fn(*args, **kwargs)
                except Exception as exc:
                    if attempt == times:
                        raise RuntimeError(f"Failed after {times} attempts") from exc
                    print(f"  Retry {attempt}/{times}: {exc}")
        return wrapper
    return decorator


# ── Dataclass ─────────────────────────────────────────────────────────────────
@dataclass
class Vector2D:
    x: float = 0.0
    y: float = 0.0
    _magnitude: Optional[float] = field(default=None, repr=False)

    def __post_init__(self) -> None:
        if not isinstance(self.x, (int, float)):
            raise TypeError(f"x must be numeric, got {type(self.x).__name__!r}")

    @property
    def magnitude(self) -> float:
        if self._magnitude is None:
            self._magnitude = math.hypot(self.x, self.y)
        return self._magnitude

    def __add__(self, other: Vector2D) -> Vector2D:
        return Vector2D(self.x + other.x, self.y + other.y)

    def __repr__(self) -> str:
        return f"Vector2D(x={self.x:.3f}, y={self.y:.3f})"

    def normalize(self) -> Vector2D:
        mag = self.magnitude
        return Vector2D(self.x / mag, self.y / mag) if mag else Vector2D()


# ── Generic class ─────────────────────────────────────────────────────────────
class Stack(Generic[T]):
    def __init__(self) -> None:
        self._items: list[T] = []

    def push(self, item: T) -> None:
        self._items.append(item)

    def pop(self) -> T:
        if not self._items:
            raise IndexError("pop from empty stack")
        return self._items.pop()

    def __len__(self) -> int:
        return len(self._items)

    def __iter__(self) -> Generator[T, None, None]:
        yield from reversed(self._items)


# ── Async ──────────────────────────────────────────────────────────────────────
async def fetch_data(url: str, timeout: float = 5.0) -> dict[str, Any]:
    """Simulate an async HTTP fetch."""
    await asyncio.sleep(0.1)
    return {"url": url, "status": 200, "data": [1, 2, 3]}


@retry(times=3)
async def reliable_fetch(url: str) -> dict:
    result = await fetch_data(url)
    if result["status"] != 200:
        raise ConnectionError(f"Bad status: {result['status']}")
    return result


# ── Comprehensions & generators ───────────────────────────────────────────────
def demonstrate_comprehensions() -> None:
    squares      = [x**2 for x in range(10) if x % 2 == 0]
    lookup       = {word: len(word) for word in ["alpha", "beta", "gamma"]}
    unique_chars = {ch for ch in "hello world" if ch != " "}
    lazy_cubes   = (x**3 for x in range(100))

    matrix       = [[row * col for col in range(1, 4)] for row in range(1, 4)]

    print(f"Squares:  {squares}")
    print(f"Lookup:   {lookup}")
    print(f"Unique:   {sorted(unique_chars)}")
    print(f"Matrix:\n" + "\n".join(f"  {row}" for row in matrix))


# ── Exception hierarchy ───────────────────────────────────────────────────────
class AppError(Exception):
    """Base application error."""
    def __init__(self, message: str, code: int = 0) -> None:
        super().__init__(message)
        self.code = code


class ValidationError(AppError):
    pass


def parse_age(value: str) -> int:
    try:
        age = int(value)
    except ValueError as exc:
        raise ValidationError(f"{value!r} is not a valid age", code=400) from exc
    if not 0 <= age <= 150:
        raise ValidationError(f"Age {age} is out of range [0, 150]", code=422)
    return age


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    v1 = Vector2D(3.0, 4.0)
    v2 = Vector2D(1.0, 2.0)
    print(v1, "magnitude =", v1.magnitude)
    print("v1 + v2 =", v1 + v2)
    print("normalized =", v1.normalize())

    s: Stack[int] = Stack()
    for n in range(5):
        s.push(n)
    print("Stack:", list(s))

    demonstrate_comprehensions()

    asyncio.run(reliable_fetch("https://example.com/api"))
