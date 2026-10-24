@echo off
setlocal enabledelayedexpansion
title Remove gbOS86 BCD Entry

net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo Removing gbOS86 entry and disabling Windows Boot Selection Menu...

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
    "bcdedit /set '{bootmgr}' displaybootmenu no; " ^
    "bcdedit /set '{bootmgr}' timeout 0; " ^
    "Write-Host '[+] Successfully cleaned BCD and disabled boot menu!' -ForegroundColor Green"

echo.
pause
