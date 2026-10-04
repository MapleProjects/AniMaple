#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUR_DIR="/home/maple/AUR/animaple-bin"
FLUTTER_BIN="/home/maple/flutter/bin/flutter"
USB_DIR="/run/media/maple/M2-512GB"

usage() {
    echo "Uso: $0 <nueva_version> [build_number] [opciones]"
    echo ""
    echo "Ejemplos:"
    echo "  $0 2.0.2 44 --publish"
    echo "  $0 2.0.2 --bump-only"
    echo ""
    echo "Opciones:"
    echo "  --bump-only     Solo sincroniza la versión en los archivos sin compilar"
    echo "  --skip-android  Omite la compilación de Android"
    echo "  --skip-linux    Omite la compilación de Linux"
    echo "  --skip-windows  Omite la compilación de Windows"
    echo "  --publish       Hace commit, tag v<version>, push y publica en GitHub Releases"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

TARGET_VERSION="$1"
shift

# Si el siguiente parámetro es un número, tomarlo como build number
TARGET_BUILD=""
if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    TARGET_BUILD="$1"
    shift
fi

BUMP_ONLY=0
SKIP_ANDROID=0
SKIP_LINUX=0
SKIP_WINDOWS=0
PUBLISH=0

while [ $# -gt 0 ]; do
    case "$1" in
        --bump-only)
            BUMP_ONLY=1
            shift
            ;;
        --skip-android)
            SKIP_ANDROID=1
            shift
            ;;
        --skip-linux)
            SKIP_LINUX=1
            shift
            ;;
        --skip-windows)
            SKIP_WINDOWS=1
            shift
            ;;
        --publish)
            PUBLISH=1
            shift
            ;;
        *)
            echo "Opción desconocida: $1"
            usage
            ;;
    esac
done

# Calcular build number si no fue especificado
if [ -z "$TARGET_BUILD" ]; then
    CURRENT_BUILD=$(grep '^version:' "$REPO_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f2)
    if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
        TARGET_BUILD=$((CURRENT_BUILD + 1))
    else
        TARGET_BUILD=1
    fi
fi

echo "=========================================="
echo " AniMaple Release Automation"
echo " Versión objetivo: $TARGET_VERSION"
echo " Build number:     $TARGET_BUILD"
echo "=========================================="

# 1. Actualizar pubspec.yaml
echo "[1/4] Actualizando pubspec.yaml..."
sed -i "s/^version: .*/version: $TARGET_VERSION+$TARGET_BUILD/" "$REPO_DIR/pubspec.yaml"

# 2. Actualizar update_service.dart
echo "[2/4] Actualizando lib/services/update_service.dart..."
sed -i "s/static const String appVersion = '.*';/static const String appVersion = '$TARGET_VERSION';/" "$REPO_DIR/lib/services/update_service.dart"

# 3. Actualizar CHANGELOG.md si no existe entrada para esta versión
echo "[3/4] Verificando CHANGELOG.md..."
if ! grep -q "## v$TARGET_VERSION" "$REPO_DIR/CHANGELOG.md"; then
    echo "Agregando sección v$TARGET_VERSION en CHANGELOG.md..."
    python3 -c "
import sys
content = open('$REPO_DIR/CHANGELOG.md', 'r', encoding='utf-8').read()
header = '# AniMaple — Registro de cambios\n'
new_entry = '''## v$TARGET_VERSION

### Novedades y mejoras
- Optimización y estabilidad en la sincronización de cuenta y copia de seguridad en la nube para televisores y dispositivos Android TV.
- Mejoras en la barra de reproducción y navegación fluida con control remoto.
- Cierre optimizado y seguro en Windows durante el proceso de actualización automática.
- Actualización del canal de releases y verificador automático para todas las plataformas.

'''
if content.startswith(header):
    updated = header + '\n' + new_entry + content[len(header):].lstrip('\n')
else:
    updated = new_entry + content
open('$REPO_DIR/CHANGELOG.md', 'w', encoding='utf-8').write(updated)
"
fi

# 4. Actualizar PKGBUILD en AUR
if [ -d "$AUR_DIR" ]; then
    echo "[4/4] Actualizando $AUR_DIR/PKGBUILD..."
    sed -i "s/^pkgver=.*/pkgver=$TARGET_VERSION/" "$AUR_DIR/PKGBUILD"
    sed -i "s/^pkgrel=.*/pkgrel=1/" "$AUR_DIR/PKGBUILD"
fi

echo "✓ Archivos de versión sincronizados correctamente con v$TARGET_VERSION+$TARGET_BUILD."

if [ "$BUMP_ONLY" -eq 1 ]; then
    echo "Finalizado (--bump-only especificado)."
    exit 0
fi

# ─────────────────────────────────────────────────────────────
# COMPILACIÓN DE PLATAFORMAS
# ─────────────────────────────────────────────────────────────

export PATH="/home/maple/flutter/bin:$PATH"

# A. Android
if [ "$SKIP_ANDROID" -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo " Compilando Android APK..."
    echo "=========================================="
    cd "$REPO_DIR"
    flutter build apk --release
    
    APK_SRC="$REPO_DIR/build/app/outputs/flutter-apk/app-release.apk"
    if [ -f "$APK_SRC" ]; then
        cp -f "$APK_SRC" /home/maple/Escritorio/app-release.apk
        if [ -d "$USB_DIR" ]; then
            echo "Copiando APK a USB $USB_DIR..."
            cp -f "$APK_SRC" "$USB_DIR/app-release.apk"
        fi
        echo "✓ APK generado: $APK_SRC"
    else
        echo "ERROR: No se encontró el APK tras compilar."
        exit 1
    fi
fi

# B. Linux
if [ "$SKIP_LINUX" -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo " Compilando Linux (Bundle + Tarball + AUR)..."
    echo "=========================================="
    cd "$REPO_DIR"
    flutter build linux --release

    DIST_LINUX="$REPO_DIR/build/linux-release"
    mkdir -p "$DIST_LINUX"
    TARBALL_NAME="animaple-v$TARGET_VERSION-linux-x86_64.tar.gz"
    TARBALL_PATH="$DIST_LINUX/$TARBALL_NAME"

    tar -czf "$TARBALL_PATH" -C "$REPO_DIR/build/linux/x64/release/bundle" animaple data lib
    echo "✓ Tarball Linux generado: $TARBALL_PATH"

    if [ -d "$AUR_DIR" ]; then
        echo "Empaquetando versión AUR..."
        TAR_SHA=$(sha256sum "$TARBALL_PATH" | awk '{print $1}')
        sed -i "s/^sha256sums=.*/sha256sums=('$TAR_SHA')/" "$AUR_DIR/PKGBUILD"
        cp -f "$TARBALL_PATH" "$AUR_DIR/animaple-bin-$TARGET_VERSION-x86_64.tar.gz"
        
        cd "$AUR_DIR"
        makepkg -f
        makepkg --printsrcinfo > .SRCINFO
        
        PKG_ZST="animaple-bin-$TARGET_VERSION-1-x86_64.pkg.tar.zst"
        cp -f "$AUR_DIR/$PKG_ZST" "$DIST_LINUX/"
        echo "✓ Paquete AUR generado: $DIST_LINUX/$PKG_ZST"
    fi
fi

# C. Windows
if [ "$SKIP_WINDOWS" -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo " Compilando Windows (VM)..."
    echo "=========================================="
    bash "$REPO_DIR/tools/build-windows.sh"
fi

# ─────────────────────────────────────────────────────────────
# PUBLICACIÓN GIT & GITHUB
# ─────────────────────────────────────────────────────────────

if [ "$PUBLISH" -eq 1 ]; then
    echo ""
    echo "=========================================="
    echo " Publicando Release en GitHub..."
    echo "=========================================="
    cd "$REPO_DIR"

    git add pubspec.yaml lib/services/update_service.dart CHANGELOG.md tools/make-release.sh
    git commit -m "release: v$TARGET_VERSION (build $TARGET_BUILD)" || true
    
    if git rev-parse "v$TARGET_VERSION" >/dev/null 2>&1; then
        git tag -d "v$TARGET_VERSION"
    fi
    git tag -a "v$TARGET_VERSION" -m "release v$TARGET_VERSION"
    
    git push origin main
    git push origin "v$TARGET_VERSION" --force

    NOTES_FILE=$(mktemp)
    python3 -c "
import sys
content = open('$REPO_DIR/CHANGELOG.md', 'r', encoding='utf-8').read()
marker = '## v$TARGET_VERSION'
if marker in content:
    sub = content.split(marker)[1]
    next_marker = '\n## '
    if next_marker in sub:
        sub = sub.split(next_marker)[0]
    open('$NOTES_FILE', 'w', encoding='utf-8').write(sub.strip())
else:
    open('$NOTES_FILE', 'w', encoding='utf-8').write('Release v$TARGET_VERSION')
"

    # Verificar existencia de release previa
    if gh release view "v$TARGET_VERSION" >/dev/null 2>&1; then
        echo "Actualizando release existente v$TARGET_VERSION..."
        gh release upload "v$TARGET_VERSION" \
            "$REPO_DIR/build/app/outputs/flutter-apk/app-release.apk" \
            "$REPO_DIR/build/linux-release/animaple-v$TARGET_VERSION-linux-x86_64.tar.gz" \
            "$REPO_DIR/build/linux-release/animaple-bin-$TARGET_VERSION-1-x86_64.pkg.tar.zst" \
            "$REPO_DIR/build/windows-release/animaple-v$TARGET_VERSION-setup.exe" \
            --clobber
    else
        echo "Creando nueva release en GitHub v$TARGET_VERSION..."
        gh release create "v$TARGET_VERSION" \
            "$REPO_DIR/build/app/outputs/flutter-apk/app-release.apk" \
            "$REPO_DIR/build/linux-release/animaple-v$TARGET_VERSION-linux-x86_64.tar.gz" \
            "$REPO_DIR/build/linux-release/animaple-bin-$TARGET_VERSION-1-x86_64.pkg.tar.zst" \
            "$REPO_DIR/build/windows-release/animaple-v$TARGET_VERSION-setup.exe" \
            --title "v$TARGET_VERSION" \
            --notes-file "$NOTES_FILE"
    fi

    rm -f "$NOTES_FILE"

    # Sincronizar repositorio git de AUR
    if [ -d "$AUR_DIR/.git" ]; then
        cd "$AUR_DIR"
        git add PKGBUILD .SRCINFO
        git commit -m "update to v$TARGET_VERSION" || true
    fi

    cd "$REPO_DIR"

    echo ""
    echo "✓ Release v$TARGET_VERSION publicada con éxito en GitHub:"
    gh release view "v$TARGET_VERSION"
fi

echo ""
echo "=========================================="
echo " Proceso de Release completado."
echo "=========================================="
