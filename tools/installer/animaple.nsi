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

RequestExecutionLevel user
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
    DetailPrint "Cerrando AniMaple si esta en ejecucion..."
    Sleep 500
    ExecWait '"$SYSDIR\cmd.exe" /c taskkill /F /T /IM animaple.exe'
    Sleep 500

    IfFileExists "$INSTDIR\animaple.exe" 0 DoneCheck
    StrCpy $R0 0
CheckLoop:
    ClearErrors
    FileOpen $R1 "$INSTDIR\animaple.exe" "a"
    IfErrors 0 FileUnlocked
    ; Sigue bloqueado por el sistema operativo o proceso residual
    ExecWait '"$SYSDIR\cmd.exe" /c taskkill /F /T /IM animaple.exe'
    Sleep 1000
    IntOp $R0 $R0 + 1
    ${If} $R0 < 10
        Goto CheckLoop
    ${EndIf}
    Goto DoneCheck
FileUnlocked:
    FileClose $R1
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
    
    DetailPrint "Ajustando atributos..."
    ExecWait 'attrib -R "$INSTDIR\*.*" /S /D'
    
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
    
    ; Clear Windows icon cache so new icon shows immediately
    DetailPrint "Actualizando cache de iconos..."
    ExecWait 'ie4uinit.exe -ClearIconCache'
    ExecWait 'ie4uinit.exe -show'
    
    ; En modo silencioso, ejecutar AniMaple automaticamente
    IfSilent 0 NotSilent
    Exec '"$INSTDIR\animaple.exe"'
NotSilent:
    
SectionEnd

;--------------------------------
; Uninstall

Function un.CloseApp
    DetailPrint "Cerrando AniMaple si esta en ejecucion..."
    Sleep 500
    ExecWait '"$SYSDIR\cmd.exe" /c taskkill /F /T /IM animaple.exe'
    Sleep 500

    IfFileExists "$INSTDIR\animaple.exe" 0 DoneUnCheck
    StrCpy $R0 0
UnCheckLoop:
    ClearErrors
    FileOpen $R1 "$INSTDIR\animaple.exe" "a"
    IfErrors 0 FileUnUnlocked
    ExecWait '"$SYSDIR\cmd.exe" /c taskkill /F /T /IM animaple.exe'
    Sleep 1000
    IntOp $R0 $R0 + 1
    ${If} $R0 < 10
        Goto UnCheckLoop
    ${EndIf}
    Goto DoneUnCheck
FileUnUnlocked:
    FileClose $R1
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
