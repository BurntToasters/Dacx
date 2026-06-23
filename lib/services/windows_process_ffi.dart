import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _CreateProcessWNative =
    Int32 Function(
      Pointer<Utf16> lpApplicationName,
      Pointer<Utf16> lpCommandLine,
      Pointer<Void> lpProcessAttributes,
      Pointer<Void> lpThreadAttributes,
      Int32 bInheritHandles,
      Uint32 dwCreationFlags,
      Pointer<Void> lpEnvironment,
      Pointer<Utf16> lpCurrentDirectory,
      Pointer<Uint8> lpStartupInfo,
      Pointer<Uint8> lpProcessInformation,
    );
typedef _CreateProcessWDart =
    int Function(
      Pointer<Utf16> lpApplicationName,
      Pointer<Utf16> lpCommandLine,
      Pointer<Void> lpProcessAttributes,
      Pointer<Void> lpThreadAttributes,
      int bInheritHandles,
      int dwCreationFlags,
      Pointer<Void> lpEnvironment,
      Pointer<Utf16> lpCurrentDirectory,
      Pointer<Uint8> lpStartupInfo,
      Pointer<Uint8> lpProcessInformation,
    );

typedef _WaitForSingleObjectNative =
    Uint32 Function(IntPtr hHandle, Uint32 dwMilliseconds);
typedef _WaitForSingleObjectDart =
    int Function(int hHandle, int dwMilliseconds);

typedef _GetExitCodeProcessNative =
    Int32 Function(IntPtr hProcess, Pointer<Uint32> lpExitCode);
typedef _GetExitCodeProcessDart =
    int Function(int hProcess, Pointer<Uint32> lpExitCode);

typedef _CloseHandleNative = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

class WindowsSpawnResult {
  final bool launched;
  final int? exitCode;
  final String? error;
  const WindowsSpawnResult({required this.launched, this.exitCode, this.error});
}

class WindowsProcessFfi {
  static const int _createNoWindow = 0x08000000;
  static const int _waitObject0 = 0x00000000;
  static const int _defaultWaitMs = 30000;

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _createProcess = _kernel32
      .lookupFunction<_CreateProcessWNative, _CreateProcessWDart>(
        'CreateProcessW',
      );
  static final _waitForSingleObject = _kernel32
      .lookupFunction<_WaitForSingleObjectNative, _WaitForSingleObjectDart>(
        'WaitForSingleObject',
      );
  static final _getExitCodeProcess = _kernel32
      .lookupFunction<_GetExitCodeProcessNative, _GetExitCodeProcessDart>(
        'GetExitCodeProcess',
      );
  static final _closeHandle = _kernel32
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  static final _getLastError = _kernel32
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  static Future<WindowsSpawnResult> runAsync(
    String commandLine, {
    String? applicationName,
    bool wait = true,
    int waitMs = _defaultWaitMs,
  }) {
    if (!Platform.isWindows) {
      return Future.value(
        const WindowsSpawnResult(
          launched: false,
          error: 'CreateProcessW is Windows-only',
        ),
      );
    }
    return Isolate.run(
      () => run(
        commandLine,
        applicationName: applicationName,
        wait: wait,
        waitMs: waitMs,
      ),
    );
  }

  static WindowsSpawnResult run(
    String commandLine, {
    String? applicationName,
    bool wait = true,
    int waitMs = _defaultWaitMs,
  }) {
    if (!Platform.isWindows) {
      return const WindowsSpawnResult(
        launched: false,
        error: 'CreateProcessW is Windows-only',
      );
    }

    final appPtr = applicationName?.toNativeUtf16();
    final cmdPtr = commandLine.toNativeUtf16();
    final startupInfo = calloc<Uint8>(104);
    final processInfo = calloc<Uint8>(24);
    startupInfo.cast<Uint32>().value = 104;

    try {
      final ok = _createProcess(
        appPtr ?? nullptr,
        cmdPtr,
        nullptr,
        nullptr,
        0,
        _createNoWindow,
        nullptr,
        nullptr,
        startupInfo,
        processInfo,
      );
      if (ok == 0) {
        return WindowsSpawnResult(
          launched: false,
          error: 'CreateProcessW failed (GetLastError=${_getLastError()})',
        );
      }

      final hProcess = processInfo.cast<IntPtr>().value;
      final hThread = (processInfo + 8).cast<IntPtr>().value;

      if (!wait) {
        _closeHandle(hThread);
        _closeHandle(hProcess);
        return const WindowsSpawnResult(launched: true);
      }

      final waitStatus = _waitForSingleObject(hProcess, waitMs);
      int? exitCode;
      if (waitStatus == _waitObject0) {
        final exitCodePtr = calloc<Uint32>();
        if (_getExitCodeProcess(hProcess, exitCodePtr) != 0) {
          exitCode = exitCodePtr.value;
        }
        calloc.free(exitCodePtr);
      }
      _closeHandle(hThread);
      _closeHandle(hProcess);
      return WindowsSpawnResult(launched: true, exitCode: exitCode);
    } finally {
      if (appPtr != null) calloc.free(appPtr);
      calloc.free(cmdPtr);
      calloc.free(startupInfo);
      calloc.free(processInfo);
    }
  }
}
