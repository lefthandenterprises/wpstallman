; build/package/installer.nsi
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

; ── Defines (defaults only if not provided via -D on makensis) ────────────────
!ifndef APP_NAME
  !define APP_NAME "W. P. Stallman"
!endif
!ifndef APP_ID
  !define APP_ID "com.wpstallman.app"
!endif
!ifndef COMPANY_NAME
  !define COMPANY_NAME "WPStallman"
!endif
!ifndef APP_VERSION
  !define APP_VERSION "0.0.0"
!endif
!ifndef VI_VERSION
  ; must be 4-part numeric for VIProductVersion
  !define VI_VERSION "0.0.0.0"
!endif
!ifndef APP_STAGE
  !define APP_STAGE ".\stage"
!endif
!ifndef OUT_EXE
  !define OUT_EXE "WPStallman-${APP_VERSION}-setup-win-x64.exe"
!endif
!ifndef APP_EXE
  !define APP_EXE "WPStallman.GUI.exe"
!endif

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"

; ── General ───────────────────────────────────────────────────────────────────
Name "${APP_NAME}"
OutFile "${OUT_EXE}"
RequestExecutionLevel admin
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "${UNINST_KEY}" "InstallLocation"
SetCompressor /SOLID lzma

; ── Version Info ──────────────────────────────────────────────────────────────
VIProductVersion "${VI_VERSION}"
VIAddVersionKey "ProductName"     "${APP_NAME}"
VIAddVersionKey "ProductVersion"  "${APP_VERSION}"
VIAddVersionKey "CompanyName"     "${COMPANY_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion"     "${VI_VERSION}"

; ── UI ────────────────────────────────────────────────────────────────────────
!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

; ── Install ───────────────────────────────────────────────────────────────────
Section "Install"
  SetOutPath "$INSTDIR"

  ; Copy staged payload
  File /r /x "*.pdb" /x "*.xml" "${APP_STAGE}\*.*"

  ; Shortcuts
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  ; Uninstall registration
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${COMPANY_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

; ── Uninstall ────────────────────────────────────────────────────────────────
Section "Uninstall"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd
