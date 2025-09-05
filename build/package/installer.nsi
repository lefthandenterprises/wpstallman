; --- NSIS installer for WPStallman ---
; Build with:
;   makensis ^
;     /DVERSION=1.0.0 ^
;     /DOUTDIR=/home/patrick/Documents/bitbucket/wpstallman/artifacts/packages ^
;     /DAPP_NAME="W. P. Stallman" ^
;     /DAPP_ID=com.wpstallman.app ^
;     /DGUI_DIR=/home/patrick/Documents/bitbucket/wpstallman/src/WPStallman.GUI/bin/Release/net8.0/win-x64/publish ^
;     /DCLI_DIR=/home/patrick/Documents/bitbucket/wpstallman/src/WPStallman.CLI/bin/Release/net8.0/win-x64/publish ^
;     /DICON_ICO=/home/patrick/Documents/bitbucket/wpstallman/artifacts/icons/WPS.ico ^
;     build/package/installer.nsi

Unicode true
!include "MUI2.nsh"

!ifndef APP_NAME
!define APP_NAME "WPStallman"
!endif

!ifndef VERSION
!define VERSION "0.0.0"
!endif

!ifndef OUTDIR
!define OUTDIR "."
!endif

!ifndef APP_ID
!define APP_ID "com.example.wpstallman"
!endif

!ifndef GUI_DIR
!define GUI_DIR "."
!endif

!ifndef CLI_DIR
!define CLI_DIR "."
!endif

!ifndef ICON_ICO
!define ICON_ICO ""
!endif

!define COMPANY_NAME "Left Hand Enterprises, LLC"
!define PRODUCT_NAME "${APP_NAME}"
!define PRODUCT_VERSION "${VERSION}"

; Output installer file (forward slashes are OK on Linux makensis)
OutFile "${OUTDIR}/${APP_NAME}-Setup-${VERSION}.exe"

; Install to Program Files (64-bit aware)
InstallDir "$ProgramFiles64\${APP_NAME}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

; Branding and icons
VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName" "${COMPANY_NAME}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME} Installer"
!if "${ICON_ICO}" != ""
Icon "${ICON_ICO}"
UninstallIcon "${ICON_ICO}"
!endif

; -------------------------------------
; Ensure 64-bit registry view where appropriate
; -------------------------------------
Function .onInit
  ; Valid place for SetRegView (NOT allowed at top-level)
  SetRegView 64
FunctionEnd

; -------------------------------------
; Pages
; -------------------------------------
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; -------------------------------------
; Sections
; -------------------------------------
Section "Install"
  SetOutPath "$InstDir"

  ; GUI payload
  SetOutPath "$InstDir\GUI"
  File /r "${GUI_DIR}\*.*"

  ; CLI payload
  SetOutPath "$InstDir\CLI"
  File /r "${CLI_DIR}\*.*"

  ; Root marker files (optional)
  SetOutPath "$InstDir"
  FileOpen $0 "$InstDir\VERSION.txt" w
  FileWrite $0 "${PRODUCT_VERSION}$\r$\n"
  FileClose $0

  ; Shortcuts
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  ; Main GUI exe guess: find the first *.exe in GUI dir (if you prefer, hard-code below)
  ; For deterministic behavior, adjust "WPStallman.GUI.exe" if your exe name differs.
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$InstDir\GUI\WPStallman.GUI.exe" "" "$InstDir\GUI\WPStallman.GUI.exe" 0
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$InstDir\GUI\WPStallman.GUI.exe" "" "$InstDir\GUI\WPStallman.GUI.exe" 0

  ; Write uninstall registry keys (using 64-bit view from .onInit)
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "Publisher" "${COMPANY_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "InstallLocation" "$InstDir"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "UninstallString" "$InstDir\Uninstall.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoRepair" 1

  ; Generate uninstaller (prevents the prior warning)
  WriteUninstaller "$InstDir\Uninstall.exe"
SectionEnd

Section "Uninstall"
  ; Remove shortcuts
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  ; Remove files
  RMDir /r "$InstDir\GUI"
  RMDir /r "$InstDir\CLI"
  Delete "$InstDir\VERSION.txt"
  Delete "$InstDir\Uninstall.exe"

  ; Try to remove install dir (only if empty)
  RMDir "$InstDir"

  ; Clean uninstall entries
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
SectionEnd
