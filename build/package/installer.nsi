; =========================================
; W.P. Stallman — NSIS Installer (MUI2)
; =========================================
!include "MUI2.nsh"
!include "x64.nsh"

; ---- Expected -D defines from the build script ----
;   -DSOURCE_DIR=".../artifacts/windows/win-x64/publish/gui"   (required)
;   -DOUT_EXE=".../artifacts/packages/nsis/WPStallman-1.0.0-Setup.exe" (required)
;   -DAPP_NAME="W.P. Stallman"                                 (default OK)
;   -DAPP_VERSION="1.0.0"                                      (default OK)
;   -DICON_FILE=".../src/WPStallman.Assets/logo/app.ico"       (default OK)
;   -DLICENSE_FILE=".../build/package/LICENSE.txt"             (default OK)
;   -DMAIN_EXE="WPStallman.GUI.exe"                            (default OK)

!ifndef SOURCE_DIR
  !error "SOURCE_DIR not defined. Call makensis with -DSOURCE_DIR=/abs/path/to/win-publish/gui"
!endif
!ifndef OUT_EXE
  !define OUT_EXE "$%TEMP%\WPStallman-Setup.exe"
!endif
!ifndef APP_NAME
  !define APP_NAME "W.P. Stallman"
!endif
!ifndef APP_VERSION
  !define APP_VERSION "0.0.0"
!endif
!ifndef ICON_FILE
  !define ICON_FILE "$%TEMP%\app.ico"
!endif
!ifndef LICENSE_FILE
  !define LICENSE_FILE "${NSISDIR}\Contrib\License.txt"
!endif
!ifndef MAIN_EXE
  !define MAIN_EXE "WPStallman.GUI.exe"
!endif

; ---- Basic installer metadata ----
Name "${APP_NAME}"
OutFile "${OUT_EXE}"
Unicode true
RequestExecutionLevel admin
BrandingText "${APP_NAME} ${APP_VERSION}"
InstallDir "$PROGRAMFILES64\${APP_NAME}"

; ---- Look & packaging ----
Icon "${ICON_FILE}"
UninstallIcon "${ICON_FILE}"
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show
XPStyle on

; ---- Version info in the installer file ----
VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName"     "${APP_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion"     "${APP_VERSION}"
VIAddVersionKey "CompanyName"     "Left Hand Enterprises, LLC"
VIAddVersionKey "LegalCopyright"  "MIT License"

; ---- MUI pages & options ----
!define MUI_ABORTWARNING
!define MUI_ICON "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"

; License page with REQUIRED checkbox (users must check "I Agree" to proceed)
!define MUI_LICENSEPAGE_CHECKBOX

; Add a Finish-page “Open the license” checkbox
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\LICENSE.txt"
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Open the license (MIT) now"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; ---- Variables ----
Var StartMenuFolder

; =========================================
; Sections
; =========================================

Section "Core Files" SEC_CORE
  SetOutPath "$INSTDIR"

  ; Copy published payload (GUI, runtimes, wwwroot, etc.)
  File /r "${SOURCE_DIR}\*"

  ; Always install/copy a stable LICENSE.txt into $INSTDIR
  SetOutPath "$INSTDIR"
  File "/oname=$INSTDIR\LICENSE.txt" "${LICENSE_FILE}"

  ; Write uninstall information (Add/Remove Programs)
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName"     "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion"  "${APP_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher"       "Left Hand Enterprises, LLC"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayIcon"     "$INSTDIR\${MAIN_EXE}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" "$INSTDIR\Uninstall.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Shortcuts" SEC_SHORTCUTS
  ; Start Menu group = App name
  StrCpy $StartMenuFolder "${APP_NAME}"

  ; Create Start Menu folder and shortcuts
  CreateDirectory "$SMPROGRAMS\$StartMenuFolder"
  CreateShortCut "$SMPROGRAMS\$StartMenuFolder\${APP_NAME}.lnk" "$INSTDIR\${MAIN_EXE}" "" "$INSTDIR\${MAIN_EXE}" 0
  CreateShortCut "$SMPROGRAMS\$StartMenuFolder\View License.lnk" "$INSTDIR\LICENSE.txt"
  CreateShortCut "$SMPROGRAMS\$StartMenuFolder\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"

  ; Optional desktop shortcut
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${MAIN_EXE}" "" "$INSTDIR\${MAIN_EXE}" 0
SectionEnd

Section -PostInstall SEC_POST
  ; (Optional) auto-run after install
  ; Exec "$INSTDIR\${MAIN_EXE}"
SectionEnd

; =========================================
; Uninstall
; =========================================
Section "Uninstall"
  ; Best-effort kill running app (commented by default)
  ; nsExec::ExecToLog 'taskkill /IM "${MAIN_EXE}" /F'

  ; Remove files and folders
  RMDir /r "$INSTDIR"

  ; Remove shortcuts
  StrCpy $StartMenuFolder "${APP_NAME}"
  Delete "$SMPROGRAMS\$StartMenuFolder\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\$StartMenuFolder\View License.lnk"
  Delete "$SMPROGRAMS\$StartMenuFolder\Uninstall ${APP_NAME}.lnk"
  RMDir  "$SMPROGRAMS\$StartMenuFolder"

  ; Remove desktop shortcut
  Delete "$DESKTOP\${APP_NAME}.lnk"

  ; Clean uninstall registry entry
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
SectionEnd
