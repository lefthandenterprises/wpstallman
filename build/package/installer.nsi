; ================================
;  WPStallman Windows Installer
; ================================

Unicode true
!include "MUI2.nsh"

; -------- /D defines with defaults --------
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

; Require ICON_ICO to be passed (we’ll validate existence in the bash wrapper)
!ifndef ICON_ICO
  !error "ICON_ICO define not passed to makensis (e.g. /DICON_ICO=/path/to/WPS.ico)"
!endif

!define COMPANY_NAME "Left Hand Enterprises, LLC"
!define PRODUCT_NAME "${APP_NAME}"
!define PRODUCT_VERSION "${VERSION}"

; -------- Identity / Branding --------
Name "${APP_NAME}"
Caption "${APP_NAME} ${VERSION}"
BrandingText "© ${COMPANY_NAME}"

; -------- Version info / Installer icons (place BEFORE OutFile) --------
VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey "ProductName"     "${PRODUCT_NAME}"
VIAddVersionKey "ProductVersion"  "${PRODUCT_VERSION}"
VIAddVersionKey "CompanyName"     "${COMPANY_NAME}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME} Installer"

; Set icons for the installer EXE and the uninstaller EXE, and MUI wizard window
Icon "${ICON_ICO}"
UninstallIcon "${ICON_ICO}"
!define MUI_ICON   "${ICON_ICO}"
!define MUI_UNICON "${ICON_ICO}"

; -------- Output file --------
OutFile "${OUTDIR}/${APP_NAME}-Setup-${VERSION}.exe"

; -------- Install location --------
InstallDir "$ProgramFiles64\${APP_NAME}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

; -------- 64-bit registry view --------
Function .onInit
  SetRegView 64
FunctionEnd

; Require a license file path (passed from the shell script)
!ifndef LICENSE_FILE
  !error "LICENSE_FILE not defined – pass -DLICENSE_FILE=/absolute/path/to/LICENSE.txt"
!endif

; -------- Pages --------
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${LICENSE_FILE}"
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
  ; GUI payload
  SetOutPath "$InstDir\GUI"
  File /r "${GUI_DIR}/*.*"

  ; CLI payload
  SetOutPath "$InstDir\CLI"
  File /r "${CLI_DIR}/*.*"

  ; Version marker
  SetOutPath "$InstDir"
  FileOpen $0 "$InstDir\VERSION.txt" w
  FileWrite $0 "${PRODUCT_VERSION}$\r$\n"
  FileClose $0

  ; Shortcuts (update exe name here if different)
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" \
                 "$InstDir\GUI\WPStallman.GUI.exe" "" "$InstDir\GUI\WPStallman.GUI.exe" 0
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" \
                 "$InstDir\GUI\WPStallman.GUI.exe" "" "$InstDir\GUI\WPStallman.GUI.exe" 0
  ; Optional: debug console shortcut
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME} (Debug Console).lnk" \
                 "$InstDir\GUI\WPStallman.GUI.exe" "--console" "$InstDir\GUI\WPStallman.GUI.exe" 0

  ; Uninstall registry keys
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayName"     "${APP_NAME}"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "Publisher"       "${COMPANY_NAME}"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayVersion"  "${PRODUCT_VERSION}"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "InstallLocation" "$InstDir"
  WriteRegStr   HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "UninstallString" "$InstDir\Uninstall.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoRepair" 1

  ; Generate uninstaller
  WriteUninstaller "$InstDir\Uninstall.exe"
SectionEnd

; =========================
;       UNINSTALL
; =========================
Section "Uninstall"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME} (Debug Console).lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"

  RMDir /r "$InstDir\GUI"
  RMDir /r "$InstDir\CLI"
  Delete "$InstDir\VERSION.txt"
  Delete "$InstDir\Uninstall.exe"
  RMDir "$InstDir"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
SectionEnd
