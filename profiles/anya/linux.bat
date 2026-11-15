@echo off
rem Restart anya into NixOS, once. Run from Windows; see dualboot.nix.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
mountvol S: /S
copy /Y S:\loader\loader-linux.conf S:\loader\loader.conf
if errorlevel 1 (
  echo Could not switch the boot menu to NixOS.
  mountvol S: /D
  pause
  exit /b 1
)
mountvol S: /D
bcdedit /set {fwbootmgr} bootsequence {e0486f75-a024-11ef-b44a-cef2b0e04cf1} >nul 2>&1
shutdown /r /t 0
