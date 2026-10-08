; Cariberry runs on Windows 10 and newer (that is what the Electron engine under her supports). On anything older the
; installer says so plainly and stops, instead of installing something that would fail to start.
; The version is read from the registry (build 10240 is the first Windows 10) so it can't be fooled by compatibility modes.
!macro customInit
  ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"
  StrCmp $R0 "" cariberryVersionOk
  IntCmp $R0 10240 cariberryVersionOk cariberryTooOld cariberryVersionOk
  cariberryTooOld:
    MessageBox MB_OK|MB_ICONEXCLAMATION "Cariberry needs Windows 10 or newer.$\r$\n$\r$\nThis PC runs an older Windows, so she can't be installed here."
    Quit
  cariberryVersionOk:
!macroend
