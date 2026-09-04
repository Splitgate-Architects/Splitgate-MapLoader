@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  make_custom_map.bat
REM  Builds a custom-map.bin from World.cf1047 + Screenshot.jpg
REM  in the current folder, matching the format of the original
REM  Splitgate: Arena Reloaded MapCreator saves.
REM ============================================================

REM --- Adjust the path to 7z.exe if it's not in the default location ---
set "SEVENZIP=C:\Program Files\7-Zip\7z.exe"
if not exist "%SEVENZIP%" set "SEVENZIP=C:\Program Files (x86)\7-Zip\7z.exe"
if not exist "%SEVENZIP%" (
    echo [ERROR] 7z.exe was not found. Please edit the path in this script.
    pause
    exit /b 1
)

set "MAPFILE=World.cf1047"
set "IMGFILE=Screenshot.jpg"
set "OUTZIP=%~dp0custom-map.zip"
set "OUTBIN=%~dp0custom-map.bin"
set "COMMENT=Packed by CreativeCore1047"

if not exist "%MAPFILE%" (
    echo [ERROR] %MAPFILE% was not found in the current folder.
    pause
    exit /b 1
)
if not exist "%IMGFILE%" (
    echo [ERROR] %IMGFILE% was not found in the current folder.
    pause
    exit /b 1
)

if exist "%OUTZIP%" del "%OUTZIP%"
if exist "%OUTBIN%" del "%OUTBIN%"

echo.
echo === Creating ZIP with 7-Zip (Deflate, order: World.cf1047 first) ===
"%SEVENZIP%" a -tzip -mx=9 -mm=Deflate "%OUTZIP%" "%MAPFILE%" "%IMGFILE%"

if not exist "%OUTZIP%" (
    echo [ERROR] ZIP could not be created.
    pause
    exit /b 1
)

echo.
echo === Setting ZIP comment to "%COMMENT%" ===
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$path = '%OUTZIP%';" ^
    "$comment = '%COMMENT%';" ^
    "$bytes = [System.IO.File]::ReadAllBytes($path);" ^
    "$commentBytes = [System.Text.Encoding]::ASCII.GetBytes($comment);" ^
    "$eocdPos = -1;" ^
    "for ($i = $bytes.Length - 22; $i -ge 0; $i--) {" ^
    "    if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) { $eocdPos = $i; break }" ^
    "}" ^
    "if ($eocdPos -eq -1) { Write-Error 'EOCD signature not found.'; exit 1 }" ^
    "$head = $bytes[0..($eocdPos + 19)];" ^
    "$newLen = [System.BitConverter]::GetBytes([UInt16]$commentBytes.Length);" ^
    "$result = New-Object byte[] ($head.Length + 2 + $commentBytes.Length);" ^
    "[Array]::Copy($head, 0, $result, 0, $head.Length);" ^
    "[Array]::Copy($newLen, 0, $result, $head.Length, 2);" ^
    "[Array]::Copy($commentBytes, 0, $result, $head.Length + 2, $commentBytes.Length);" ^
    "[System.IO.File]::WriteAllBytes($path, $result);" ^
    "Write-Host 'Comment set successfully.'"

if errorlevel 1 (
    echo [ERROR] Could not set the comment.
    pause
    exit /b 1
)

ren "%OUTZIP%" "custom-map.bin"

echo.
echo === Done: %OUTBIN% ===
pause
