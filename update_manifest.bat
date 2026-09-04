@echo off
REM Runs update_manifest.ps1 from this same folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_manifest.ps1"
pause