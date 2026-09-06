@echo off
REM Runs script_update_manifest.ps1 from this same folder.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0script_update_manifest.ps1"
pause