; ================================
;  WPStallman Windows Installer
;  Build with makensis and /D defines
; ================================

Unicode true
!include "MUI2.nsh"

; -------- Command-line /D defines (with safe defaults) --------
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

; -------- Identity / Branding (fixes "Name" showing in the UI) --------
Name "${APP_NAME}"
Caption "${APP_NAME} ${VERSION}"
BrandingText "© ${COMPANY_NAME}"

; -------- Install location (64-bit Program Files) --------
InstallDir "$ProgramFiles64\${APP_NAME}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

; -------- Version info / Icons for the installer EXE --------
VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName"       "${PRODUCT_NAME}"
VIAddVersionKey "ProductVersion"    "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName"       "${COMPANY_NAME}"
VIAddVersionKey "FileDescription"   "${PRODUCT_NAME} Installer"

!if "${ICON_ICO}" != ""
  Icon "${ICON_ICO}"
  UninstallIcon "${ICON_ICO}"
!endif

; -------- Output file --------
OutFile "${OUTDIR}/${APP_NAME}-Setup-${VERSION}.exe"

; -------- Ensure 64-bit registry view for writes --------
Function .onInit
  SetRegView 64
FunctionEnd

; -------- Pages --------
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; =========================
;        INSTALL
; =========================
Section "Install"
  ; -- Copy GUI payload --
  SetOutPath "$InstDir\GUI"
  File /r "${GUI_DIR}/*.*"

  ; -- Copy CLI payload --
  SetOutPath "$InstDir\CLI"
  File /r "${CLI_DIR}/*.*"

  ; -- Drop a version marker --
  SetOutPath "$InstDir"
  FileOpen $0 "$InstDir\VERSION.txt" w
  FileWrite $0 "${PRODUCT_VERSION}$\r$\n"
  FileClose $0

  ; -- Shortcuts (update EXE name here if different) --
  ; If your published GUI exe has another name, change WPStallman.GUI.exe below.
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" \
                 "$InstDir\GUI\WPStallman.GUI.exe" "" "$InstDir\GUI\WPStallman.GUI.exe" 0
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" \
                 "$InstDir\GUI\WPStallman.GUI.exe" "" "$InstDir\GUI\WPStallman.GUI.exe" 0

  ; Optional: a debug shortcut that opens with a console window
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME} (Debug Console).lnk" \
                 "$InstDir\GUI\WPStallman.GUI.exe" "--console" "$InstDir\GUI\WPStallman.GUI.exe" 0

  ; -- Uninstall registry keys --
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayName"    "${APP_NAME}"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "Publisher"      "${COMPANY_NAME}"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "InstallLocation" "$InstDir"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "UninstallString" "$InstDir\Uninstall.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoRepair" 1

  ; -- Generate the uninstaller --
  WriteUninstaller "$InstDir\Uninstall.exe"
SectionEnd

; =========================
;       UNINSTALL
; =========================
Section "Uninstall"
  ; Remove shortcuts
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME} (Debug Console).lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  ; Remove files/dirs
  RMDir /r "$InstDir\GUI"
  RMDir /r "$InstDir\CLI"
  Delete "$InstDir\VERSION.txt"
  Delete "$InstDir\Uninstall.exe"

  ; Try to remove install directory (only if empty)
  RMDir "$InstDir"

  ; Clean registry
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
SectionEnd
