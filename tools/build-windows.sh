#!/usr/bin/env bash
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="Windows11"
VM_IP="192.168.122.237"
VM_USER="Maple"

echo "=== AniMaple Windows Native Build ==="
echo "Directorio del proyecto: $REPO_DIR"

# 1. Verificar estado de la máquina virtual
VM_STATE=$(sudo virsh domstate "$VM_NAME" 2>/dev/null || echo "shut off")
if [ "$VM_STATE" != "ejecutando" ] && [ "$VM_STATE" != "running" ]; then
    echo "Iniciando máquina virtual $VM_NAME..."
    sudo virsh start "$VM_NAME"
    echo "Esperando que Windows y SSH inicien..."
    until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 "$VM_USER@$VM_IP" "hostname" >/dev/null 2>&1; do
        sleep 2
    done
fi

echo "Conexión SSH confirmada con $VM_USER@$VM_IP."

# 2. Extraer versión de pubspec.yaml
VERSION=$(grep '^version:' "$REPO_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)
echo "Versión detectada: v$VERSION"

# 3. Sincronizar código fuente a la máquina virtual vía tar sobre SSH
echo "Sincronizando código fuente a C:\\Users\\$VM_USER\\AniMaple..."
ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" '
if (Test-Path "C:\Users\Maple\AniMaple") {
    # Conservar .dart_tool o build si se desea incremental, o limpiar
    Get-ChildItem "C:\Users\Maple\AniMaple" -Exclude "build", ".dart_tool" | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType Directory -Path "C:\Users\Maple\AniMaple" -Force | Out-Null
}
'

tar --exclude='.git' \
    --exclude='build' \
    --exclude='.dart_tool' \
    --exclude='*.qcow2' \
    --exclude='*.iso' \
    -czf - -C "$REPO_DIR" . | ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" 'tar -xzf - -C C:\Users\Maple\AniMaple'

echo "Código fuente sincronizado exitosamente."

# 4. Compilar proyecto en Windows con Flutter y MSVC
echo "Ejecutando flutter pub get y flutter build windows --release..."
ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "
cd C:\Users\Maple\AniMaple
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat build windows --release
"

# 5. Generar instalador con NSIS y paquete ZIP portátil
echo "Generando instalador NSIS y comprimido portátil..."
ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" '
Set-Location "C:\Users\Maple\AniMaple\tools\installer"
& "C:\Program Files (x86)\NSIS\makensis.exe" /DVERSION="'"$VERSION"'" /DBUILD_DIR="C:\Users\Maple\AniMaple\build\windows\x64\runner\Release" /DINSTALLER_DIR="C:\Users\Maple\AniMaple\tools\installer" animaple.nsi
Compress-Archive -Path "C:\Users\Maple\AniMaple\build\windows\x64\runner\Release\*" -DestinationPath "C:\Users\Maple\AniMaple\tools\installer\animaple-v'"$VERSION"'-windows.zip" -Force
'

# 6. Copiar instalador y paquete portable al host
DIST_DIR="$REPO_DIR/build/windows-release"
mkdir -p "$DIST_DIR"
echo "Copiando binarios finales a $DIST_DIR..."
scp -o StrictHostKeyChecking=no "$VM_USER@$VM_IP:C:/Users/Maple/AniMaple/tools/installer/animaple-v$VERSION-setup.exe" "$DIST_DIR/"
scp -o StrictHostKeyChecking=no "$VM_USER@$VM_IP:C:/Users/Maple/AniMaple/tools/installer/animaple-v$VERSION-windows.zip" "$DIST_DIR/"

echo "=== Compilación completada con éxito ==="
ls -lh "$DIST_DIR"
