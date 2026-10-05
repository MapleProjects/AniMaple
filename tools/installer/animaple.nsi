; NSIS template for AniMaple
; Version is injected by build-windows script from pubspec.yaml
; Installs to $LOCALAPPDATA, supports updates without deleting data

;--------------------------------
; Includes

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

;--------------------------------
; Config — VERSION, BUILD_DIR y INSTALLER_DIR son inyectados por el script
; de build con -DVERSION=... / -DBUILD_DIR=... / -DINSTALLER_DIR=...
; !define VERSION "X.Y.Z"
; !define BUILD_DIR "C:\...\build\windows\x64\runner\Release"
; !define INSTALLER_DIR "C:\...\dist"
!ifndef INSTALLER_DIR
  !define INSTALLER_DIR "."
!endif

Name "AniMaple"
OutFile "${INSTALLER_DIR}\animaple-v${VERSION}-setup.exe"

InstallDir "$LOCALAPPDATA\AniMaple"
InstallDirRegKey HKCU "Software\AniMaple" "InstallPath"

RequestExecutionLevel admin
SetCompressor /SOLID lzma

Icon "${INSTALLER_DIR}\app_icon.ico"
UninstallIcon "${INSTALLER_DIR}\app_icon.ico"

;--------------------------------
; Interface

!define MUI_ABORTWARNING
!define MUI_ICON "${INSTALLER_DIR}\app_icon.ico"
!define MUI_UNICON "${INSTALLER_DIR}\app_icon.ico"

!define MUI_WELCOMEPAGE_TITLE "Bienvenido al instalador de AniMaple"
!define MUI_WELCOMEPAGE_TEXT "Este asistente le guiara en la instalacion de AniMaple v${VERSION}.$\r$\n$\r$\nEl programa se instalara en su carpeta de usuario.$\r$\n$\r$\nHaga clic en Siguiente para continuar."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_TITLE "Instalacion completada"
!define MUI_FINISHPAGE_TEXT "AniMaple se ha instalado correctamente."
!define MUI_FINISHPAGE_RUN "$INSTDIR\animaple.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Ejecutar AniMaple"

!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Spanish"

;--------------------------------
; Variables

Var isUpdate

;--------------------------------
; Functions

Function CloseApp
    DetailPrint "Cerrando instancias previas de AniMaple..."
    ; 1. Cerrar cualquier otro instalador previo colgado
    System::Call 'kernel32::GetCurrentProcessId() i .r0'
    nsExec::Exec '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -WindowStyle Hidden -Command "Get-Process | Where-Object { ($$_.ProcessName -match \"animaple.*setup\" -or $$_.MainWindowTitle -match \"Instalaci[oó]n de AniMaple\") -and $$_.Id -ne $0 } | Stop-Process -Force -ErrorAction SilentlyContinue"'

    ; 2. Terminar animaple.exe de forma completamente silenciosa
    nsExec::Exec '"$SYSDIR\taskkill.exe" /F /T /IM animaple.exe'
    nsExec::Exec '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -WindowStyle Hidden -Command "Get-Process -Name animaple -ErrorAction SilentlyContinue | Stop-Process -Force"'
    Sleep 500

    IfFileExists "$INSTDIR\animaple.exe" 0 DoneCheck
    StrCpy $R0 0
CheckLoop:
    ClearErrors
    Delete "$INSTDIR\animaple.exe"
    IfFileExists "$INSTDIR\animaple.exe" 0 FileUnlocked
    ; Sigue bloqueado: reintentar terminacion forzada
    nsExec::Exec '"$SYSDIR\taskkill.exe" /F /T /IM animaple.exe'
    nsExec::Exec '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -WindowStyle Hidden -Command "Get-Process -Name animaple -ErrorAction SilentlyContinue | Stop-Process -Force"'
    Sleep 500
    IntOp $R0 $R0 + 1
    ${If} $R0 < 6
        Goto CheckLoop
    ${EndIf}
    ; Si persiste bloqueo, renombrar el archivo para permitir instalar
    Rename "$INSTDIR\animaple.exe" "$INSTDIR\animaple.exe.old.$R0"
    Delete /REBOOTOK "$INSTDIR\animaple.exe.old.$R0"
    Goto DoneCheck
FileUnlocked:
DoneCheck:
FunctionEnd

Function .onInit
    ReadRegStr $0 HKCU "Software\AniMaple" "InstallPath"
    ${If} $0 != ""
        StrCpy $INSTDIR $0
        StrCpy $isUpdate "1"
    ${Else}
        StrCpy $INSTDIR "$LOCALAPPDATA\AniMaple"
        StrCpy $isUpdate "0"
    ${EndIf}
    Call CloseApp
FunctionEnd

;--------------------------------
; Main Section

Section "AniMaple" SecMain
    
    ; Asegurar que la aplicacion este completamente cerrada y desbloqueada
    DetailPrint "Asegurando que AniMaple este cerrado..."
    Call CloseApp
    
    ; Install (overwrites files, keeps data)
    CreateDirectory "$INSTDIR"
    SetOutPath "$INSTDIR"
    
    DetailPrint "Copiando archivos..."
    File /r "${BUILD_DIR}\*.*"
    
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    
    DetailPrint "Creando accesos directos..."
    CreateDirectory "$SMPROGRAMS\AniMaple"
    CreateShortcut "$SMPROGRAMS\AniMaple\AniMaple.lnk" "$INSTDIR\animaple.exe"
    CreateShortcut "$SMPROGRAMS\AniMaple\Desinstalar.lnk" "$INSTDIR\Uninstall.exe"
    CreateShortcut "$DESKTOP\AniMaple.lnk" "$INSTDIR\animaple.exe"
    
    ; Registry
    WriteRegStr HKCU "Software\AniMaple" "InstallPath" "$INSTDIR"
    WriteRegStr HKCU "Software\AniMaple" "Version" "${VERSION}"
    
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple" "DisplayName" "AniMaple"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple" "DisplayIcon" "$INSTDIR\animaple.exe"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple" "Publisher" "MapleProjects"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple" "URLInfoAbout" "https://github.com/MapleProjects/AniMaple"
    
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple" "EstimatedSize" "$0"
    
    ; Notificar al shell de Windows de cambios de iconos de forma instantanea sin consola
    System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
    
    ; En modo silencioso, ejecutar AniMaple automaticamente
    IfSilent 0 NotSilent
    Exec '"$INSTDIR\animaple.exe"'
NotSilent:
    
SectionEnd

;--------------------------------
; Uninstall

Function un.CloseApp
    DetailPrint "Cerrando instancias previas de AniMaple..."
    nsExec::Exec '"$SYSDIR\taskkill.exe" /F /T /IM animaple.exe'
    nsExec::Exec '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -WindowStyle Hidden -Command "Get-Process -Name animaple -ErrorAction SilentlyContinue | Stop-Process -Force"'
    Sleep 500

    IfFileExists "$INSTDIR\animaple.exe" 0 DoneUnCheck
    StrCpy $R0 0
UnCheckLoop:
    ClearErrors
    Delete "$INSTDIR\animaple.exe"
    IfFileExists "$INSTDIR\animaple.exe" 0 FileUnUnlocked
    nsExec::Exec '"$SYSDIR\taskkill.exe" /F /T /IM animaple.exe'
    nsExec::Exec '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -WindowStyle Hidden -Command "Get-Process -Name animaple -ErrorAction SilentlyContinue | Stop-Process -Force"'
    Sleep 500
    IntOp $R0 $R0 + 1
    ${If} $R0 < 6
        Goto UnCheckLoop
    ${EndIf}
    Rename "$INSTDIR\animaple.exe" "$INSTDIR\animaple.exe.old"
    Delete /REBOOTOK "$INSTDIR\animaple.exe.old"
    Goto DoneUnCheck
FileUnUnlocked:
DoneUnCheck:
FunctionEnd

Function un.onInit
    Call un.CloseApp
FunctionEnd

Section "Uninstall"
    Call un.CloseApp
    Sleep 1000
    
    RMDir /r "$INSTDIR"
    
    Delete "$DESKTOP\AniMaple.lnk"
    RMDir /r "$SMPROGRAMS\AniMaple"
    
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple"
    DeleteRegKey HKCU "Software\AniMaple"
    
    MessageBox MB_OK "AniMaple ha sido desinstalado correctamente."
SectionEnd
