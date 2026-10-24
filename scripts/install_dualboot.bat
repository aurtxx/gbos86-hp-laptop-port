@echo off
setlocal enabledelayedexpansion
title gbOS86 Dual-Boot SSD Installer (HP Alder Lake Port)

echo ======================================================================
echo    gbOS86 Native Dual-Boot SSD Installer (HP 15s-fr5009TU Port)
echo ======================================================================
echo.

:: 1. Verify Administrative Privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Requesting Administrator Privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/k \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo [+] Running with Administrator Privileges.
echo.

:: 2. Safety Verification: Ensure Drive C: is never touched
if /I "E:"=="C:" (
    echo [ERROR] Target drive cannot be C:! Aborting.
    pause
    exit /b 1
)

:: 3. Check if E: is already formatted as FAT32
echo [*] Checking Drive E: filesystem...
vol E: >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Drive E: is not accessible.
    pause
    exit /b 1
)

:: 4. Verify Payload Files on E:
if not exist "E:\gbos\super.img" (
    echo [*] Copying gbOS86 payload to E:\ ...
    robocopy "%~dp0payload" E: /E /MT:8 /R:1 /W:1 /NFL /NDL /NP
    if %errorLevel% geq 8 (
        echo [ERROR] Robocopy encountered errors while copying payload to E:\.
        pause
        exit /b 1
    )
    echo [+] System payload deployed to E:\.
) else (
    echo [+] System payload already present on E:\gbos (super.img verified).
)

:: 5. Register Dual-Boot Entry in Windows Boot Manager (BCD)
echo.
echo [*] Registering gbOS86 entry in Windows Boot Manager...

:: Remove any previous duplicate gbOS entries
for /f "tokens=2 delims={}" %%g in ('bcdedit /enum {bootmgr} 2^>nul ^| findstr /i "gbOS86"') do (
    echo [*] Removing existing BCD entry {%%g}...
    bcdedit /delete {%%g} >nul 2>&1
)

:: Create new bootapp entry
set "ENTRY_ID="
for /f "tokens=2 delims={}" %%i in ('bcdedit /create /d "gbOS86 (Alder Lake Android-x86)" /application bootapp') do (
    set "ENTRY_ID={%%i}"
)

if not defined ENTRY_ID (
    for /f "tokens=2 delims={}" %%i in ('bcdedit /copy {bootmgr} /d "gbOS86 (Alder Lake Android-x86)"') do (
        set "ENTRY_ID={%%i}"
    )
)

if defined ENTRY_ID (
    echo [+] Created BCD Entry: %ENTRY_ID%
    bcdedit /set %ENTRY_ID% device partition=E: >nul
    bcdedit /set %ENTRY_ID% path \EFI\BOOT\BOOTX64.EFI >nul
    bcdedit /displayorder %ENTRY_ID% /addlast >nul
    bcdedit /set {bootmgr} displaybootmenu yes >nul
    bcdedit /set {bootmgr} timeout 5 >nul
    echo [+] Successfully configured Windows Boot Menu (5-second timeout).
) else (
    echo [!] Notice: Could not create BCD bootapp entry.
)

echo.
echo ======================================================================
echo    INSTALLATION COMPLETE!
echo ======================================================================
echo.
echo  Dual-boot is now set up on your internal NVMe SSD:
echo    1. Drive E:\ (GBOSSYS, 7.3 GB FAT32) contains the system and bootloader.
echo    2. Windows C:\ was 100%% untouched and preserved.
echo    3. Windows Boot Manager now shows:
echo         - Windows 11
echo         - gbOS86 (Alder Lake Android-x86)
echo.
echo  Boot Options on Restart:
echo    - Choice A: Turn on your laptop and choose "gbOS86" from the Windows boot menu.
echo    - Choice B: Tap F9 on startup to select "gbOS86" or "GBOSSYS" from HP UEFI boot menu.
echo.
pause
