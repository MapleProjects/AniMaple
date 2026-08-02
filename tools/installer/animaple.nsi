; NSIS template for AniMaple
; Version is injected by build-windows script from pubspec.yaml
; Installs to $LOCALAPPDATA, supports updates without deleting data

;--------------------------------
; Includes

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"

;--------------------------------
; Config — VERSION and BUILD_DIR injected by build script
; !define VERSION "X.Y.Z"
; !define BUILD_DIR "C:\Users\WinterOS\AniMaple\build\windows\x64\runner\Release"

Name "AniMaple"
OutFile "C:\Users\WinterOS\installer\animaple-v${VERSION}-setup.exe"

InstallDir "$LOCALAPPDATA\AniMaple"
InstallDirRegKey HKCU "Software\AniMaple" "InstallPath"

RequestExecutionLevel user
SetCompressor /SOLID lzma

Icon "C:\Users\WinterOS\installer\app_icon.ico"
UninstallIcon "C:\Users\WinterOS\installer\app_icon.ico"

;--------------------------------
; Interface

!define MUI_ABORTWARNING
!define MUI_ICON "C:\Users\WinterOS\installer\app_icon.ico"
!define MUI_UNICON "C:\Users\WinterOS\installer\app_icon.ico"

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

Function .onInit
    StrCpy $isUpdate "0"
    ReadRegStr $0 HKCU "Software\AniMaple" "InstallPath"
    ${If} $0 != ""
        StrCpy $isUpdate "1"
    ${EndIf}
FunctionEnd

Function CloseApp
    nsExec::ExecToStack 'taskkill /F /IM animaple.exe'
    Pop $0
    Pop $1
    Sleep 1000
FunctionEnd

;--------------------------------
; Main Section

Section "AniMaple" SecMain
    
    ; Close app if updating
    ${If} $isUpdate == "1"
        DetailPrint "Cerrando AniMaple para actualizar..."
        Call CloseApp
    ${EndIf}
    
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
    
SectionEnd

;--------------------------------
; Uninstall

Section "Uninstall"
    nsExec::ExecToStack 'taskkill /F /IM animaple.exe'
    Pop $0
    Pop $1
    Sleep 1000
    
    RMDir /r "$INSTDIR"
    
    Delete "$DESKTOP\AniMaple.lnk"
    RMDir /r "$SMPROGRAMS\AniMaple"
    
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AniMaple"
    DeleteRegKey HKCU "Software\AniMaple"
    
    MessageBox MB_OK "AniMaple ha sido desinstalado correctamente."
SectionEnd
