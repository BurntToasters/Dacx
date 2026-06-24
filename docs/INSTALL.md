# Install Dacx
This is a quick writeup on how to install Dacx on Windows, macOS, and Linux:

### Windows:
* **x64:** Download and run the latest `.MSI` x64 installer **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Windows-x64.msi)**.
* **arm64:** Dacx does not have a native arm64 version for Windows, however installing the x64 `.MSI` installer should work: **[x64 Installer](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Windows-x64.msi)**.

### macOS:
* **Universal (x64 and arm64):** Download the latest `.DMG` release and move `Dacx.app` into your `/Applications` folder. Download the DMG **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-macOS.dmg)**.

### Linux:
The recommended install method is to either use the AppImage with [App Manager](https://github.com/kem-a/AppManager) (or on its own), or to use the Flatpak binary (experimental).

* **AppImage (x64):** Download the latest AppImage binary **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.AppImage)**.
* **Flatpak (x64):** Download the latest Flatpak binary **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.flatpak)**.
  * After downloading the flatpak, please install it on your system via: `flatpak install --user /path-to-flatpak-installer.flatpak`.
* **Ubuntu/Debian (x64):** Download the latest DEB package: **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-amd64.deb)**.
* **Fedora (x64):** Download the latest RPM package: **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.rpm)**.
* **OTHER (x64):** I also provide a generic unpackaged binary **[HERE](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.tar.gz)**.

**ARM64:** There is no support for Linux arm64 on Dacx. This is not a priority of mine due to the low user-base of arm64 linux. If this project gets popular and it becomes a widely requested feature, it may be something I would look into.