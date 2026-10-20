# Unwanted Native Library Failure Inventory

Release packaging must fail closed when the desktop bundle contains the JNI
bridge `dartjni`. Dacx never uses JNI on desktop, so any `dartjni` binary in the
bundle is an unsigned, unused payload that the Windows MSI or Linux packages
would ship.

`checkUnwantedNativeLibs` and the packaging guard must fail for these cases:

- `dartjni.dll` sits at the top level of the Windows bundle directory.
- `libdartjni.so` sits at the top level of the Linux bundle directory.
- A `dartjni` library sits in a nested directory, such as the Linux bundle `lib/`.
- The name differs only in case on Windows, such as `DartJni.dll`.
- The bundle directory is missing, so the guard cannot prove the bundle is clean.
- The CMake disable flag `CMAKE_DISABLE_FIND_PACKAGE_JNI` is placed after
  `include(flutter/generated_plugins.cmake)`, so the jni plugin still finds JNI.

The guard must not fail for unrelated native libraries:

- `libmpv-2.dll` and `libmpv.so.2` in the bundle pass.
- A clean bundle with only Flutter, plugin, and runtime DLLs or shared objects passes.
