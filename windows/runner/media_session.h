#pragma once

#include <flutter/binary_messenger.h>

namespace dacx {

void RegisterMediaSession(flutter::BinaryMessenger* messenger);
void UnregisterMediaSession(flutter::BinaryMessenger* messenger);

}  // namespace dacx
