@echo off
set PROJECT_NAME=debian-simple-server-setup
set TEST_DISTRO=%PROJECT_NAME%-test
set CLEAN_DISTRO=Debian
set WSL_ROOT=D:\WSL
set TEST_ROOT=%WSL_ROOT%\%TEST_DISTRO%
set CLEAN_IMAGE=%WSL_ROOT%\%PROJECT_NAME%-clean.tar
echo WARNING:
echo This will DELETE the WSL distro: %TEST_DISTRO%
echo It will NOT touch: %CLEAN_DISTRO%
choice /M "Continue"
if errorlevel 2 exit /b

wsl --terminate %TEST_DISTRO% >nul 2>&1
wsl --unregister %TEST_DISTRO% >nul 2>&1
wsl --import %TEST_DISTRO% %TEST_ROOT% %CLEAN_IMAGE%
echo Test distro reset complete.
pause
