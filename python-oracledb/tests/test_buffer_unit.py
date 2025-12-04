"""Unit tests for the low-level Buffer Cython implementation."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

import pytest

ROOT_DIR = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT_DIR / "src"
TESTS_DIR = Path(__file__).resolve().parent
BUILD_DIR = ROOT_DIR / "build" / "pyximport"
NANOARROW_DIR = SRC_DIR / "oracledb" / "impl" / "arrow" / "nanoarrow"

def _ensure_distutils() -> None:
    try:  # Python <= 3.11
        import distutils  # type: ignore # pragma: no cover
        return
    except ModuleNotFoundError:
        pass

    try:
        import setuptools  # noqa: F401
    except ImportError as exc:  # pragma: no cover - toolchain missing
        raise RuntimeError("setuptools is required to build Cython helpers") from exc

    module_map = {
        "distutils": "setuptools._distutils",
        "distutils.core": "setuptools._distutils.core",
        "distutils.command": "setuptools._distutils.command",
        "distutils.cmd": "setuptools._distutils.cmd",
        "distutils.dist": "setuptools._distutils.dist",
        "distutils.extension": "setuptools._distutils.extension",
        "distutils.errors": "setuptools._distutils.errors",
        "distutils.log": "setuptools._distutils.log",
        "distutils.sysconfig": "setuptools._distutils.sysconfig",
    }
    for alias, target in module_map.items():
        if alias not in sys.modules:
            sys.modules[alias] = importlib.import_module(target)


_ensure_distutils()

try:
    import pyximport
except ImportError:  # pragma: no cover - Cython not installed
    pyximport = None

if pyximport is None:  # pragma: no cover - skip when compiler missing
    pytest.skip("pyximport (Cython) is required for buffer unit tests",
                allow_module_level=True)

for path in (SRC_DIR, TESTS_DIR):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

BUILD_DIR.mkdir(parents=True, exist_ok=True)

pyximport.install(
    language_level=3,
    build_dir=str(BUILD_DIR),
    setup_args={
        "include_dirs": [str(SRC_DIR), str(NANOARROW_DIR)],
    },
)

from _buffer_test_helper import TestableBuffer, TestableGrowableBuffer  # noqa: E402


def _make_buffer(max_size: int = 64) -> TestableBuffer:
    buf = TestableBuffer()
    buf.initialize(max_size)
    return buf


def _make_growable(max_size: int = 8) -> TestableGrowableBuffer:
    buf = TestableGrowableBuffer()
    buf.initialize(max_size)
    return buf


def test_write_read_uint8_roundtrip() -> None:
    buf = _make_buffer()
    buf.write_uint8_public(255)
    buf.finalize_for_read()
    assert buf.read_uint8_public() == 255


def test_write_uint16be_byte_order() -> None:
    buf = _make_buffer()
    buf.write_uint16be_public(0x1234)
    assert buf.snapshot()[:2] == bytes([0x12, 0x34])


def test_utf8_string_round_trip() -> None:
    buf = _make_buffer()
    text = "Cafe\u00e9 mundo"
    encoded = text.encode("utf-8")
    buf.write_ub4_public(len(encoded))
    buf.write_bytes_with_length_public(encoded)
    buf.finalize_for_read()
    assert buf.read_str_with_length_public() == text


def test_growable_buffer_resizes_automatically() -> None:
    buf = _make_growable(max_size=8)
    buf.write_bytes_public(b"A" * 20)
    assert buf.max_size() >= 20


def test_oracle_number_zero_encoding() -> None:
    buf = _make_buffer()
    buf.write_oracle_number_public(b"0")
    raw = buf.snapshot()
    assert raw[0] == 1  # length byte
    assert raw[1] == 128  # oracle zero marker
