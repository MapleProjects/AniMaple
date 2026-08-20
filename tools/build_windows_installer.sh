#!/usr/bin/env bash
# AniMaple — build Windows release + NSIS installer (reproducible)
# Uso:  bash tools/build_windows_installer.sh
# Produce: dist/animaple-v<VERSION>-setup.exe
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

export PATH="$HOME/flutter/flutter/bin:$PATH"
if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter no está en el PATH. Instálalo y agrégalo a PATH." >&2
  exit 1
fi

MAKENSIS="/c/Program Files (x86)/NSIS/makensis.exe"
if [ ! -f "$MAKENSIS" ]; then
  echo "ERROR: No se encontró makensis en $MAKENSIS. Instala NSIS." >&2
  exit 1
fi

# --- paso 1: compilar app Windows release ---
echo "==> Compilando AniMaple (Windows release)…"
# Secret opcional de Google OAuth desktop: se inyecta vía entorno para NO
# quedarse en el repo. Uso:  GOOGLE_DESKTOP_CLIENT_SECRET=... bash tools/...
DART_DEFINES=""
if [ -n "${GOOGLE_DESKTOP_CLIENT_SECRET:-}" ]; then
  DART_DEFINES="--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=${GOOGLE_DESKTOP_CLIENT_SECRET}"
  echo "==> Inyectando GOOGLE_DESKTOP_CLIENT_SECRET (oculto)"
fi
flutter build windows --release $DART_DEFINES

# --- paso 2: preparar dist/ e inyectar version ---
RELEASE_DIR="$ROOT/build/windows/x64/runner/Release"
DIST_DIR="$ROOT/dist"
VERSION="$(grep -m1 -E '^version:' pubspec.yaml | sed -E 's/^version: *//; s/\+.*//')"
echo "==> Versión detectada: $VERSION"

mkdir -p "$DIST_DIR"
cp -f tools/installer/app_icon.ico "$DIST_DIR/app_icon.ico"

# --- paso 3: compilar instalador NSIS ---
echo "==> Generando instalador NSIS…"
# makensis.exe es un binario nativo de Windows: necesita rutas estilo
# Windows (C:/...), no las rutas POSIX de git-bash (MSYS) que no abre.
WIN_RELEASE="$(cygpath -w "$RELEASE_DIR" | tr '\\' '/')"
WIN_DIST="$(cygpath -w "$DIST_DIR" | tr '\\' '/')"
"$MAKENSIS" \
  -DVERSION="$VERSION" \
  -DBUILD_DIR="$WIN_RELEASE" \
  -DINSTALLER_DIR="$WIN_DIST" \
  tools/installer/animaple.nsi

echo
echo "==> ¡Listo! Instalador generado:"
echo "    $DIST_DIR/animaple-v${VERSION}-setup.exe"