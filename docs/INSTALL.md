# Install Dacx
This is a quick writeup on how to install Dacx on Windows, macOS, and Linux:

### Windows:
* **x64:** Download and run the latest `.MSI` x64 installer **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Windows-x64.msi)**.
* **arm64:** Dacx does not have a native arm64 version for Windows, however installing the x64 `.MSI` installer should work: **[x64 Installer](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Windows-x64.msi)**.

### macOS:
* **Universal (x64 and arm64):** Download the latest `.DMG` release and move `Dacx.app` into your `/Applications` folder. Download the DMG **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-macOS.dmg)**.
  * **IMPORTANT:** The Dacx auto-updater **ONLY** works if the application is inside the main `/Applications` folder.

### Linux:
**Recommended:** AppImage + [AppManager](https://github.com/kem-a/AppManager).

1. Download the latest AppImage **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.AppImage)**.
2. Install [AppManager](https://github.com/kem-a/AppManager) (double-click its AppImage or follow their docs).
3. Open the Dacx AppImage with AppManager (or drag it into AppManager) to install desktop integration and manage updates.

AppManager can keep AppImages updated in the background (including optional GitHub-aware update checks). Dacx itself has **no** in-app Linux self-updater, but as previously stated if you input this repo's GitHub URL into the app's update section in AppManager, you will have AppImage updates!

#### Other Linux packages (optional)
* **Ubuntu/Debian (x64):** **[DEB](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-amd64.deb)**; install the new `.deb` from the release page when updating.
* **Fedora (x64):** **[RPM](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.rpm)**; same idea with the `.rpm`.
* **Flatpak (x64, optional sideload):** **[`.flatpak`](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.flatpak)**; GitHub sideload only (not Flathub). `flatpak install --user …`; reinstall to update.
* **Generic tarball (x64):** **[TAR.GZ](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.tar.gz)**; unpack and run; replace the tree to update.

**ARM64:** There is no support for Linux arm64 on Dacx. This is not a priority of mine due to the low user-base of arm64 linux. If this project gets popular and it becomes a widely requested feature, it may be something I would look into.
