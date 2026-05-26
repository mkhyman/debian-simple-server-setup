@echo off
set PROJECT_NAME=debian-simple-server-setup
set DEBIAN_VERSION=13

REM Must match the locally installed Debian WSL distro name.
set CLEAN_DISTRO=Debian-%DEBIAN_VERSION%

set TEST_DISTRO=%PROJECT_NAME%-debian-%DEBIAN_VERSION%-test

set WSL_ROOT=D:\WSL
set TEST_ROOT=%WSL_ROOT%\%TEST_DISTRO%
set CLEAN_IMAGE=%WSL_ROOT%\%PROJECT_NAME%-debian-%DEBIAN_VERSION%-clean.tar

echo Exporting clean Debian image...
echo Source distro: %CLEAN_DISTRO%
echo Output image : %CLEAN_IMAGE%
wsl --export %CLEAN_DISTRO% %CLEAN_IMAGE%
echo Done.
pause
