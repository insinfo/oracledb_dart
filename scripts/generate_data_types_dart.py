from __future__ import annotations

from pathlib import Path
import re

DATA_TYPES_PATH = Path("python-oracledb/src/oracledb/impl/thin/messages/data_types.pyx")
MERGED_CODE_PATH = Path("scripts/merged_code.dart.txt")

assign_re = re.compile(r"^(?:cdef\s+\w+\s+)?(\w+)\s*=\s*(.+)$")
dart_const_re = re.compile(r"^const\s+int\s+(\w+)\s*=\s*([^;]+);")


def build_constants_and_entries(path: Path):
    consts: dict[str, int] = load_dart_constants(MERGED_CODE_PATH)
    entries: list[tuple[int, int, int]] = []
    data_types_started = False

    for raw_line in path.read_text().splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("cdef DataType") and "DATA_TYPES" in line:
            data_types_started = True
            continue
        if data_types_started:
            if line.startswith("["):
                entry_text = line.strip().rstrip(",")
                entry_text = entry_text.strip("[]")
                if entry_text:
                    parts = [part.strip() for part in entry_text.split(",")]
                    values = tuple(_eval_expr(part, consts) for part in parts)
                    if len(values) != 3:
                        raise ValueError(f"Unexpected entry: {line}")
                    entries.append(values)
            elif line.startswith("]"):
                break
            continue
        match = assign_re.match(line)
        if match:
            name, expr = match.groups()
            try:
                consts[name] = _eval_expr(expr, consts)
            except NameError:
                # forward declaration; skip
                pass
    return consts, entries


def _eval_expr(expr: str, consts: dict[str, int]) -> int:
    return int(eval(expr, {}, consts))


def load_dart_constants(path: Path) -> dict[str, int]:
    consts: dict[str, int] = {}
    if not path.exists():
        return consts
    pending: list[tuple[str, str]] = []
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        match = dart_const_re.match(line)
        if match:
            pending.append(match.groups())
    unresolved = True
    while unresolved and pending:
        unresolved = False
        remaining: list[tuple[str, str]] = []
        for name, expr in pending:
            try:
                consts[name] = _eval_expr(expr, consts)
            except NameError:
                unresolved = True
                remaining.append((name, expr))
        if unresolved and len(remaining) == len(pending):
            raise RuntimeError("Unable to resolve some constants from merged_code.dart.txt")
        pending = remaining
    return consts


def emit_dart(entries: list[tuple[int, int, int]]) -> str:
    lines = ["const List<List<int>> kDataTypes = ["]
    for data_type, conv_data_type, rep in entries:
        lines.append(f"  [{data_type}, {conv_data_type}, {rep}],")
    lines.append("];\n")
    return "\n".join(lines)


def main():
    consts, entries = build_constants_and_entries(DATA_TYPES_PATH)
    dart_source = emit_dart(entries)
    Path("scripts/generated_data_types.dart.txt").write_text(dart_source)
    print("Wrote generated_data_types.dart.txt with", len(entries), "entries")


if __name__ == "__main__":
    main()
