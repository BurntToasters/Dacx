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

install(TARGETS dacx-update-helper RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
