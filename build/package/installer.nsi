; ===== WPStallman NSIS Installer (Windows) =====

!ifndef SOURCE_DIR
  !error "SOURCE_DIR not defined. Call makensis with -DSOURCE_DIR=/abs/path/to/win-publish"
!endif

!ifndef APP_NAME
  !define APP_NAME "WPStallman"
!endif
!ifndef APP_ID
  !define APP_ID "com.wpstallman.app"
!endif
!ifndef APP_DESC
  !define APP_DESC "Document your entire MySQL database in MarkDown format"
!endif
!ifndef APPVER
  !define APPVER "0.0.0"
!endif
!ifndef APPVER_NUM
  !define APPVER_NUM "1.0.0.0"
!endif
!ifndef EXE_NAME
  !define EXE_NAME "WPStallman.GUI.exe"
!endif
!ifndef OUT_EXE
  !define OUT_EXE "WPStallman-Setup-${APPVER}.exe"
!endif

!ifdef ICON_FILE
  !define HAVE_ICON 1
!endif
!ifdef UNICON_FILE
  !define HAVE_UNICON 1
!endif

!include "MUI2.nsh"
!include "FileFunc.nsh"

OutFile "${OUT_EXE}"
Name "${APP_NAME}"
BrandingText "${APP_NAME} ${APPVER}"
Caption "${APP_NAME} Installer"

VIProductVersion "${APPVER_NUM}"
VIAddVersionKey "ProductName"     "${APP_NAME}"
VIAddVersionKey "FileDescription" "${APP_DESC}"
VIAddVersionKey "ProductVersion"  "${APPVER}"
VIAddVersionKey "FileVersion"     "${APPVER}"

!ifdef HAVE_ICON
  Icon "${ICON_FILE}"
!endif
!ifdef HAVE_UNICON
  UninstallIcon "${UNICON_FILE}"
!endif

RequestExecutionLevel admin
InstallDir "$ProgramFiles64\${APP_NAME}"
InstallDirRegKey HKLM "Software\${APP_NAME}" "Install_Dir"

SetCompress auto
SetCompressor /SOLID lzma

; --------- Build-time (Linux) sanity check ---------
; If you're building on Linux, this verifies SOURCE_DIR exists before File /r
!system 'test -d "${SOURCE_DIR}" || (echo "ERR: SOURCE_DIR not found: ${SOURCE_DIR}" >&2; exit 1)'

!define MUI_ABORTWARNING
!ifdef ICON_FILE
  !define MUI_ICON "${ICON_FILE}"
!endif
!ifdef UNICON_FILE
  !define MUI_UNICON "${UNICON_FILE}"
!endif
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE_NAME}"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "-Install core"
  SetRegView 64
  SetOutPath "$INSTDIR"

  DetailPrint "Packaging payload from: ${SOURCE_DIR}"

  ; IMPORTANT: This copies files at **build time** from your Linux path
  SetOverwrite ifnewer
  File /r "${SOURCE_DIR}/*"

  ; Save install path
  WriteRegStr HKLM "Software\${APP_NAME}" "Install_Dir" "$INSTDIR"

  ; Uninstall entry
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayName"     "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "DisplayVersion"  "${APPVER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "Publisher"       "Left Hand Enterprises, LLC"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}" "InstallLocation" "$INSTDIR"

  ; Uninstaller & shortcuts
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${EXE_NAME}" "" "$INSTDIR\${EXE_NAME}" 0
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  SetRegView 64
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "Software\${APP_NAME}"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
SectionEnd
