WSL test environment helpers for debian-simple-server-setup.

Edit variables at the top of the .bat files if needed.

Recommended workflow:

1. create-clean-image.bat
   Exports your clean Debian WSL install.

2. rebuild-and-open-test-distro.bat
   Resets the disposable test distro and opens a shell.

3. Test the repo inside the disposable distro.

Your normal Debian WSL install is not modified.
