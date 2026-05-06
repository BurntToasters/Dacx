#ifndef RUNNER_INSTANCE_BRIDGE_H_
#define RUNNER_INSTANCE_BRIDGE_H_

#include <flutter/binary_messenger.h>

#include <string>
#include <vector>

namespace dacx {

bool AllowMultipleInstancesEnabled();

// Returns true if --new-instance was passed and removes that flag from |args|.
bool ConsumeNewInstanceFlag(std::vector<std::string>& args);

// Tries to forward |file_paths| to an already-running primary instance via the
// named pipe IPC. Returns true on success (caller should exit), false if no
// primary instance is running or the send failed.
bool ForwardToRunningInstance(const std::vector<std::string>& file_paths);

// Acquires the named singleton mutex. Returns false if another instance owns
// it. The mutex is held for the lifetime of the process.
bool AcquireSingletonMutex();

// Starts the named-pipe server that receives file paths from secondary
// instances. Forwarded paths are dispatched to Flutter via the
// "run.rosie.dacx/open_file" channels registered on |messenger|.
void StartOpenFileServer(flutter::BinaryMessenger* messenger);

}  // namespace dacx

#endif  // RUNNER_INSTANCE_BRIDGE_H_
