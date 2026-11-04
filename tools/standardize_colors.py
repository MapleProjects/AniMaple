#!/usr/bin/env python3
"""Reemplaza literales Color(0x...) por tokens de AppColors.

Uso: python3 tools/standardize_colors.py [--dry-run]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
TOKENS_FILE = LIB / "ui" / "tokens.dart"

# Tokens exactos, ordenados por valor.
EXACT: dict[int, str] = {
    0xFF0A0812: "AppColors.bg",
    0xFF07050D: "AppColors.bgDeep",
    0xFF110E1A: "AppColors.surface",
    0xFF1A1530: "AppColors.surfaceHigh",
    0xFF241B45: "AppColors.surfaceHighest",
    0xFF1E1832: "AppColors.outline",
    0xFF3B2F5C: "AppColors.outlineStrong",
    0xFF8B5CF6: "AppColors.primary",
    0xFFA78BFA: "AppColors.primaryBright",
    0xFF7C3AED: "AppColors.primaryDeep",
    0xFFEC4899: "AppColors.accent",
    0xFFE8E4F0: "AppColors.text",
    0xFFF3F0FA: "AppColors.textStrong",
    0xFFA99FC0: "AppColors.textSecondary",
    0xFF6D6488: "AppColors.textMuted",
    0xFF4A4260: "AppColors.textDisabled",
    0xFF22C55E: "AppColors.success",
    0xFFF59E0B: "AppColors.warning",
    0xFFEF4444: "AppColors.danger",
    0xFFF87171: "AppColors.dangerSoft",
    0xFF3B82F6: "AppColors.info",
    0x14FFFFFF: "AppColors.glass",
    0x24FFFFFF: "AppColors.glassStrong",
    0x1FFFFFFF: "AppColors.glassBorder",
    0x99000000: "AppColors.veil",
    0xCC0A0812: "AppColors.scrim",
    0x990A0812: "AppColors.scrimSoft",
    0xE60A0812: "AppColors.bgStrong",
    0xF20A0812: "AppColors.bgOpaque",
    0x000A0812: "AppColors.bgClear",
}

# Paleta para aproximar valores fuera de catálogo.
PALETTE: dict[int, str] = {
    0xFF0A0812: "AppColors.bg",
    0xFF07050D: "AppColors.bgDeep",
    0xFF110E1A: "AppColors.surface",
    0xFF1A1530: "AppColors.surfaceHigh",
    0xFF241B45: "AppColors.surfaceHighest",
    0xFF1E1832: "AppColors.outline",
    0xFF3B2F5C: "AppColors.outlineStrong",
    0xFF8B5CF6: "AppColors.primary",
    0xFFA78BFA: "AppColors.primaryBright",
    0xFF7C3AED: "AppColors.primaryDeep",
    0xFFEC4899: "AppColors.accent",
    0xFFE8E4F0: "AppColors.text",
    0xFFF3F0FA: "AppColors.textStrong",
    0xFFA99FC0: "AppColors.textSecondary",
    0xFF6D6488: "AppColors.textMuted",
    0xFF4A4260: "AppColors.textDisabled",
    0xFF22C55E: "AppColors.success",
    0xFFF59E0B: "AppColors.warning",
    0xFFEF4444: "AppColors.danger",
    0xFF3B82F6: "AppColors.info",
}

COLOR_RE = re.compile(r"Color\(0x([0-9A-Fa-f]{8})\)")


def nearest(value: int) -> str:
    r, g, b = (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF
    best, best_d = None, 1 << 30
    for candidate, name in PALETTE.items():
        cr, cg, cb = (candidate >> 16) & 0xFF, (candidate >> 8) & 0xFF, candidate & 0xFF
        # Distancia ponderada por percepción aproximada.
        d = 2 * (r - cr) ** 2 + 4 * (g - cg) ** 2 + 3 * (b - cb) ** 2
        if d < best_d:
            best, best_d = name, d
    return best or "AppColors.surface"


def resolve(raw: str) -> str:
    value = int(raw, 16)
    if value in EXACT:
        return EXACT[value]
    return nearest(value)


def import_line(path: Path) -> str:
    rel = Path("ui/tokens.dart")
    depth = len(path.relative_to(LIB).parts) - 1
    prefix = "../" * depth
    return f"import '{prefix}{rel.as_posix()}';"


def main() -> int:
    dry = "--dry-run" in sys.argv
    changed_files = 0
    replacements = 0

    for path in sorted(LIB.rglob("*.dart")):
        if path == TOKENS_FILE or "ui/tokens.dart" in path.as_posix():
            continue
        text = path.read_text(encoding="utf-8")
        if "Color(0x" not in text:
            continue

        def sub(match: re.Match[str]) -> str:
            nonlocal replacements
            replacements += 1
            return resolve(match.group(1))

        new_text = COLOR_RE.sub(sub, text)
        if new_text == text:
            continue

        # Añadir import si falta.
        imp = import_line(path)
        if imp not in new_text:
            lines = new_text.splitlines()
            insert_at = 0
            for i, line in enumerate(lines):
                if line.startswith("import "):
                    insert_at = i + 1
            lines.insert(insert_at, imp)
            new_text = "\n".join(lines) + "\n"

        changed_files += 1
        if not dry:
            path.write_text(new_text, encoding="utf-8")

    print(f"archivos modificados: {changed_files}")
    print(f"reemplazos: {replacements}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
