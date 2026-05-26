WSL test environment helpers for debian-simple-server-setup.

Configuration:
- Debian version is explicit (currently Debian 13).
- CLEAN_DISTRO must match the installed WSL distro name.
- Default storage location is D:\WSL.

Recommended workflow:

1. create-clean-image.bat
   Exports your clean Debian WSL image.

2. rebuild-and-open-test-distro.bat
   Deletes and recreates the disposable test distro.

3. Test the repo inside the disposable distro.

Your normal Debian WSL install is not modified.
