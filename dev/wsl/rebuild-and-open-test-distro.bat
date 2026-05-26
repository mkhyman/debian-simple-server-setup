@echo off
set PROJECT_NAME=debian-simple-server-setup
set TEST_DISTRO=%PROJECT_NAME%-test
set CLEAN_DISTRO=Debian
set WSL_ROOT=D:\WSL
set TEST_ROOT=%WSL_ROOT%\%TEST_DISTRO%
set CLEAN_IMAGE=%WSL_ROOT%\%PROJECT_NAME%-clean.tar
call "%~dp0reset-test-distro.bat"
wsl -d %TEST_DISTRO%
