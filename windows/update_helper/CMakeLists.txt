cmake_minimum_required(VERSION 3.14)
project(dacx_update_helper LANGUAGES CXX)

# Silent GUI-subsystem helper: wait for Dacx to exit, re-verify the MSI, elevate msiexec.
add_executable(dacx-update-helper WIN32
  "main.cpp"
)

apply_standard_settings(dacx-update-helper)
target_compile_definitions(dacx-update-helper PRIVATE "NOMINMAX")
target_link_libraries(dacx-update-helper PRIVATE
  bcrypt.lib
  crypt32.lib
  wintrust.lib
  shell32.lib
  advapi32.lib
)

# Land next to dacx.exe (Flutter's installable app dir). Relying on install(TARGETS)
# alone left the helper in update_helper/Release while packaging reads runner/Release.
set_target_properties(dacx-update-helper PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "$<TARGET_FILE_DIR:${BINARY_NAME}>"
)

# Ensure `flutter build windows` always builds the helper with the app.
add_dependencies(${BINARY_NAME} dacx-update-helper)
