#!/usr/bin/env python3
"""生成 GBK / GB18030 解码表（供 Dart 端离线解码 UTF-8 之外的中文文本）。

用法：python3 tool/encoding/generate_gbk_table.py
输出：lib/utils/gbk_table_data.dart（生成文件，勿手改）

两张表：
  1. 双字节表：lead 0x81..0xFE × trail 0x40..0xFE（跳过 0x7F），每个码位 2 字节大端，
     未映射为 0xFFFD。
  2. 四字节区间表：每两项一组 (起始指针, 起始 Unicode)，区间内映射是线性的
     （与 WHATWG encoding standard 的 gb18030 ranges 一致），用于 GB18030 四字节
     生僻字/表情。
"""
from __future__ import annotations

import base64
import os

LEADS = range(0x81, 0xFF)
TRAILS = [t for t in range(0x40, 0xFF) if t != 0x7F]
UNMAPPED = 0xFFFD


def build_double_byte_table() -> tuple[bytes, int]:
    buf = bytearray()
    mapped = 0
    for lead in LEADS:
        for trail in TRAILS:
            try:
                code = ord(bytes([lead, trail]).decode("gbk"))
            except (UnicodeDecodeError, ValueError):
                code = UNMAPPED
            if code > 0xFFFF:  # GBK 双字节不会越过 BMP
                code = UNMAPPED
            if code != UNMAPPED:
                mapped += 1
            buf += code.to_bytes(2, "big")
    return bytes(buf), mapped


def four_byte_bytes(pointer: int) -> bytes:
    first = 0x81 + pointer // (10 * 1260)
    rest = pointer % (10 * 1260)
    second = 0x30 + rest // 1260
    rest2 = rest % 1260
    third = 0x81 + rest2 // 10
    fourth = 0x30 + rest2 % 10
    return bytes([first, second, third, fourth])


def four_byte_code_point(pointer: int) -> int:
    try:
        return ord(four_byte_bytes(pointer).decode("gb18030"))
    except (UnicodeDecodeError, ValueError):
        return UNMAPPED


def build_four_byte_ranges() -> list[int]:
    pointers = list(range(0, 39420)) + list(range(189000, 1237576))
    pairs = [(pointer, four_byte_code_point(pointer)) for pointer in pointers]
    ranges: list[tuple[int, int]] = []
    for pointer, code in pairs:
        if ranges:
            start_pointer, start_code = ranges[-1]
            if (
                code != UNMAPPED
                and start_code != UNMAPPED
                and code - pointer == start_code - start_pointer
            ):
                continue
        ranges.append((pointer, code))
    # 校验：任何指针都能由区间表线性还原
    for pointer, code in pairs:
        start_pointer, start_code = ranges[0]
        for candidate_pointer, candidate_code in ranges:
            if candidate_pointer > pointer:
                break
            start_pointer, start_code = candidate_pointer, candidate_code
        if start_code + (pointer - start_pointer) != code:
            raise AssertionError(f"range table mismatch at pointer {pointer}")
    return [value for pair in ranges for value in pair]


def main() -> None:
    table, mapped = build_double_byte_table()
    encoded = base64.b64encode(table).decode("ascii")
    chunks = [encoded[i : i + 96] for i in range(0, len(encoded), 96)]
    ranges = build_four_byte_ranges()
    range_lines: list[str] = []
    for i in range(0, len(ranges), 16):
        row = ", ".join(str(value) for value in ranges[i : i + 16])
        range_lines.append(f"    {row},")

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out = os.path.join(root, "lib", "utils", "gbk_table_data.dart")
    lines = [
        "// GENERATED FILE - DO NOT EDIT BY HAND.",
        "// 由 tool/encoding/generate_gbk_table.py 生成。",
        "",
        "/// GBK 双字节解码表（base64，每个码位 2 字节大端；未映射为 0xFFFD）。",
        "/// 顺序：lead 0x81..0xFE × trail 0x40..0xFE（跳过 0x7F），共 126×190 个码位。",
        "const String kGbkTableBase64 =",
        "\n".join(f"    '{chunk}'" for chunk in chunks) + ";",
        "",
        "/// GB18030 四字节区间表：每两项一组 (起始指针, 起始 Unicode)，区间内线性映射。",
        "const List<int> kGb18030FourByteRanges = <int>[",
        *range_lines,
        "];",
        "",
    ]
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print(f"wrote {out}")
    print(f"double-byte: entries={len(table) // 2} mapped={mapped} base64={len(encoded)}")
    print(f"four-byte: ranges={len(ranges) // 2}")


if __name__ == "__main__":
    main()
