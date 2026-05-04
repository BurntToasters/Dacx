#pragma once

#include <flutter/binary_messenger.h>

namespace dacx {

// Registers the SMTC media-session method-channel handler on
// `run.rosie.dacx/media_session`. Lifetime is bound to the engine.
void RegisterMediaSession(flutter::BinaryMessenger* messenger);

}  // namespace dacx
