@echo off
setlocal enabledelayedexpansion
title Remove Windows Boot Selection Menu

:: 1. Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Requesting Administrator Privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo ======================================================================
echo    Removing gbOS86 from Windows Boot Menu
echo ======================================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$raw = bcdedit /enum all; " ^
    "$curId = ''; " ^
    "$toDelete = @(); " ^
    "foreach ($line in $raw) { " ^
    "    if ($line -match 'identifier\s+(\{[0-9a-fA-F\-]+\})') { $curId = $matches[1] } " ^
    "    if ($line -match 'gbOS86' -and $curId -ne '') { $toDelete += $curId } " ^
    "} " ^
    "foreach ($id in ($toDelete | Select-Object -Unique)) { " ^
    "    Write-Host '[*] Deleting BCD entry:' $id; " ^
    "    bcdedit /delete $id; " ^
    "} " ^
    "Write-Host '[*] Disabling Windows Boot Menu and setting timeout to 0...'; " ^
    "bcdedit /set '{bootmgr}' displaybootmenu no; " ^
    "bcdedit /set '{bootmgr}' timeout 0; " ^
    "Write-Host '[+] Successfully removed boot menu!' -ForegroundColor Green"

echo.
echo ======================================================================
echo Windows Boot Manager will now boot Windows directly with no menu.
echo To boot gbOS86 directly: Tap F9 on startup to choose gbOS86/UEFI.
echo ======================================================================
echo.
pause
