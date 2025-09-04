; ===== Minimal NSIS installer for WPStallman (Windows x64) =====
Unicode true
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!include "MUI2.nsh"

; ---- Defines (overridden by makensis /D...) ----
!ifndef APP_NAME
  !define APP_NAME "W. P. Stallman"
!endif
!ifndef APP_ID
  !define APP_ID "com.wpstallman.app"
!endif
!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!ifndef OUTDIR
  !define OUTDIR "..\..\artifacts\packages"
!endif

; Where the published binaries are (win-x64 publish folders)
!ifndef GUI_PAYLOAD
  !define GUI_PAYLOAD "..\..\src\WPStallman.GUI\bin\Release\net8.0\win-x64\publish"
!endif
!ifndef CLI_PAYLOAD
  !define CLI_PAYLOAD "..\..\src\WPStallman.CLI\bin\Release\net8.0\win-x64\publish"
!endif

Name "${APP_NAME}"
OutFile "${OUTDIR}\WPStallman-${VERSION}-setup-win-x64.exe"
InstallDir "$PROGRAMFILES64\WPStallman"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$InstDir"

  ; GUI files
  IfFileExists "${GUI_PAYLOAD}\*.*" 0 +3
    SetOutPath "$InstDir"
    File /r "${GUI_PAYLOAD}\*.*"

  ; CLI files
  IfFileExists "${CLI_PAYLOAD}\*.*" 0 +3
    SetOutPath "$InstDir\cli"
    File /r "${CLI_PAYLOAD}\*.*"

  ; Shortcuts (Start Menu + optional Desktop)
  CreateDirectory "$SMPROGRAMS\WPStallman"
  CreateShortcut "$SMPROGRAMS\WPStallman\WPStallman.lnk" "$InstDir\WPStallman.GUI.exe"
  CreateShortcut "$DESKTOP\WPStallman.lnk" "$InstDir\WPStallman.GUI.exe"

  ; Uninstaller
  WriteUninstaller "$InstDir\Uninstall.exe"

  ; Add Add/Remove Programs entry
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "Publisher" "WPStallman"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "InstallLocation" "$InstDir"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayIcon" "$InstDir\WPStallman.GUI.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "UninstallString" "$InstDir\Uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\WPStallman\WPStallman.lnk"
  RMDir  "$SMPROGRAMS\WPStallman"
  Delete "$DESKTOP\WPStallman.lnk"

  ; Remove files
  RMDir /r "$InstDir\cli"
  RMDir /r "$InstDir"

  ; Remove ARP entry
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
SectionEnd
