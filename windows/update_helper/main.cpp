// dacx-update-helper.exe: post-exit Windows MSI installer watchdog.
//
// Spawned outside Dacx's Job Object (via WMI from Dart) so it survives
// Process Lifetime Management when the app calls exit(0) after starting an update.
//
// Usage:
//   dacx-update-helper.exe --pid <dacxPid> --msi <path> --sha256 <64hex>
//                          [--thumbprint <hex>] [--publisher <name>]
//                          [--exe <dacx.exe>] [--relaunch 0|1]
//
// After a successful msiexec, relaunches Dacx (default) like the macOS updater.
//
// Exit codes (aligned with the former PowerShell watchdog):
//   0    success
//   2    wait/OpenProcess error
//   5    timeout waiting for Dacx
//  10    Authenticode status not Valid
//  11    Authenticode thumbprint mismatch
//  12    SHA-256 mismatch
//  13    bad/missing arguments
//  99    fatal / unexpected
// 1223   msiexec / UAC launch failed

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
// NOMINMAX comes from target_compile_definitions in CMakeLists.txt (same as runner).

#include <windows.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <wincrypt.h>
#include <wintrust.h>
#include <softpub.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "wintrust.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")

namespace {

constexpr DWORD kWaitTimeoutMs = 600000;  // 10 minutes

std::wstring ToHexLower(const BYTE* data, size_t len) {
  static const wchar_t* kHex = L"0123456789abcdef";
  std::wstring out;
  out.resize(len * 2);
  for (size_t i = 0; i < len; ++i) {
    out[i * 2] = kHex[(data[i] >> 4) & 0xF];
    out[i * 2 + 1] = kHex[data[i] & 0xF];
  }
  return out;
}

std::string NarrowUtf8(const std::wstring& s) {
  if (s.empty()) return {};
  const int n = WideCharToMultiByte(CP_UTF8, 0, s.data(),
                                    static_cast<int>(s.size()), nullptr, 0,
                                    nullptr, nullptr);
  if (n <= 0) return {};
  std::string out(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}

std::wstring LocalAppData() {
  wchar_t buf[MAX_PATH];
  const DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return {};
  return std::wstring(buf, n);
}

void LogLine(const std::wstring& msg) {
  const std::wstring base = LocalAppData();
  if (base.empty()) return;
  const std::wstring dir = base + L"\\Dacx\\updates";
  CreateDirectoryW((base + L"\\Dacx").c_str(), nullptr);
  CreateDirectoryW(dir.c_str(), nullptr);
  const std::wstring file = dir + L"\\helper.log";

  SYSTEMTIME st{};
  GetSystemTime(&st);
  wchar_t ts[64];
  swprintf_s(ts, L"%04u-%02u-%02uT%02u:%02u:%02uZ", st.wYear, st.wMonth,
             st.wDay, st.wHour, st.wMinute, st.wSecond);

  const std::wstring line = std::wstring(ts) + L" " + msg + L"\r\n";
  HANDLE h =
      CreateFileW(file.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                  OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  const std::string utf8 = NarrowUtf8(line);
  WriteFile(h, utf8.data(), static_cast<DWORD>(utf8.size()), &written, nullptr);
  CloseHandle(h);
}

std::wstring NormalizeThumbprint(std::wstring value) {
  std::wstring out;
  out.reserve(value.size());
  for (wchar_t c : value) {
    if ((c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f') ||
        (c >= L'A' && c <= L'F')) {
      if (c >= L'a' && c <= L'f') c = static_cast<wchar_t>(c - L'a' + L'A');
      out.push_back(c);
    }
  }
  return out;
}

bool Sha256File(const std::wstring& path, std::wstring* out_hex) {
  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  NTSTATUS st =
      BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
  if (st < 0) return false;

  DWORD hash_len = 0;
  DWORD cb = 0;
  st = BCryptGetProperty(alg, BCRYPT_HASH_LENGTH,
                         reinterpret_cast<PUCHAR>(&hash_len), sizeof(hash_len),
                         &cb, 0);
  if (st < 0 || hash_len == 0) {
    BCryptCloseAlgorithmProvider(alg, 0);
    return false;
  }

  st = BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0);
  if (st < 0) {
    BCryptCloseAlgorithmProvider(alg, 0);
    return false;
  }

  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    return false;
  }

  std::vector<BYTE> buf(1 << 16);
  for (;;) {
    DWORD read = 0;
    if (!ReadFile(file, buf.data(), static_cast<DWORD>(buf.size()), &read,
                  nullptr)) {
      CloseHandle(file);
      BCryptDestroyHash(hash);
      BCryptCloseAlgorithmProvider(alg, 0);
      return false;
    }
    if (read == 0) break;
    st = BCryptHashData(hash, buf.data(), read, 0);
    if (st < 0) {
      CloseHandle(file);
      BCryptDestroyHash(hash);
      BCryptCloseAlgorithmProvider(alg, 0);
      return false;
    }
  }
  CloseHandle(file);

  std::vector<BYTE> digest(hash_len);
  st = BCryptFinishHash(hash, digest.data(), hash_len, 0);
  BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(alg, 0);
  if (st < 0) return false;

  *out_hex = ToHexLower(digest.data(), digest.size());
  return true;
}

bool VerifyAuthenticode(const std::wstring& path,
                        const std::wstring& expected_thumbprint,
                        const std::wstring& expected_publisher,
                        int* exit_code) {
  WINTRUST_FILE_INFO file_info{};
  file_info.cbStruct = sizeof(file_info);
  file_info.pcwszFilePath = path.c_str();

  GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  WINTRUST_DATA data{};
  data.cbStruct = sizeof(data);
  data.dwUIChoice = WTD_UI_NONE;
  data.fdwRevocationChecks = WTD_REVOKE_NONE;
  data.dwUnionChoice = WTD_CHOICE_FILE;
  data.pFile = &file_info;
  data.dwStateAction = WTD_STATEACTION_VERIFY;
  data.dwProvFlags = WTD_SAFER_FLAG;

  const LONG status = WinVerifyTrust(nullptr, &action, &data);
  data.dwStateAction = WTD_STATEACTION_CLOSE;
  WinVerifyTrust(nullptr, &action, &data);

  if (status != ERROR_SUCCESS) {
    LogLine(L"authenticode status not Valid");
    *exit_code = 10;
    return false;
  }

  HCERTSTORE store = nullptr;
  HCRYPTMSG msg = nullptr;
  if (!CryptQueryObject(CERT_QUERY_OBJECT_FILE, path.c_str(),
                        CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
                        CERT_QUERY_FORMAT_FLAG_BINARY, 0, nullptr, nullptr,
                        nullptr, &store, &msg, nullptr)) {
    LogLine(L"CryptQueryObject failed");
    *exit_code = 10;
    return false;
  }

  DWORD signer_info_size = 0;
  CryptMsgGetParam(msg, CMSG_SIGNER_INFO_PARAM, 0, nullptr, &signer_info_size);
  std::vector<BYTE> signer_info_buf(signer_info_size);
  auto* signer_info =
      reinterpret_cast<CMSG_SIGNER_INFO*>(signer_info_buf.data());
  if (!CryptMsgGetParam(msg, CMSG_SIGNER_INFO_PARAM, 0, signer_info,
                        &signer_info_size)) {
    CryptMsgClose(msg);
    CertCloseStore(store, 0);
    LogLine(L"CryptMsgGetParam failed");
    *exit_code = 10;
    return false;
  }

  CERT_INFO cert_info{};
  cert_info.Issuer = signer_info->Issuer;
  cert_info.SerialNumber = signer_info->SerialNumber;
  PCCERT_CONTEXT cert =
      CertFindCertificateInStore(store, X509_ASN_ENCODING, 0,
                                 CERT_FIND_SUBJECT_CERT, &cert_info, nullptr);
  if (cert == nullptr) {
    CryptMsgClose(msg);
    CertCloseStore(store, 0);
    LogLine(L"signer certificate not found");
    *exit_code = 10;
    return false;
  }

  bool identity_matches = false;
  if (!expected_publisher.empty()) {
    const DWORD name_len = CertGetNameStringW(
        cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr, nullptr, 0);
    std::vector<wchar_t> name(name_len);
    if (name_len <= 1 ||
        CertGetNameStringW(cert, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr,
                           name.data(), name_len) == 0) {
      LogLine(L"publisher read failed");
    } else {
      const std::wstring actual_publisher(name.data());
      identity_matches =
          _wcsicmp(actual_publisher.c_str(), expected_publisher.c_str()) == 0;
      if (!identity_matches) {
        LogLine(L"authenticode publisher mismatch expected=" +
                expected_publisher + L" actual=" + actual_publisher);
      }
    }
  } else {
    DWORD hash_len = 0;
    CertGetCertificateContextProperty(cert, CERT_SHA1_HASH_PROP_ID, nullptr,
                                      &hash_len);
    std::vector<BYTE> hash(hash_len);
    if (CertGetCertificateContextProperty(cert, CERT_SHA1_HASH_PROP_ID,
                                          hash.data(), &hash_len)) {
      const std::wstring actual =
          NormalizeThumbprint(ToHexLower(hash.data(), hash.size()));
      identity_matches =
          _wcsicmp(actual.c_str(), expected_thumbprint.c_str()) == 0;
      if (!identity_matches) {
        LogLine(L"authenticode thumbprint mismatch expected=" +
                expected_thumbprint + L" actual=" + actual);
      }
    } else {
      LogLine(L"thumbprint read failed");
    }
  }
  CertFreeCertificateContext(cert);
  CryptMsgClose(msg);
  CertCloseStore(store, 0);
  if (!identity_matches) {
    *exit_code = 11;
    return false;
  }
  return true;
}

int WaitForPid(DWORD pid) {
  HANDLE proc =
      OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (proc == nullptr) {
    const DWORD err = GetLastError();
    if (err == ERROR_INVALID_PARAMETER || err == ERROR_INVALID_HANDLE) {
      LogLine(L"pid already gone");
      return 0;
    }
    LogLine(L"OpenProcess failed");
    return 2;
  }
  const DWORD wait = WaitForSingleObject(proc, kWaitTimeoutMs);
  CloseHandle(proc);
  if (wait == WAIT_TIMEOUT) {
    LogLine(L"timeout waiting for pid");
    return 5;
  }
  if (wait != WAIT_OBJECT_0) {
    LogLine(L"WaitForSingleObject failed");
    return 2;
  }
  return 0;
}

int LaunchMsiexec(const std::wstring& msi_path) {
  wchar_t system_root[MAX_PATH];
  const DWORD n = GetEnvironmentVariableW(L"SystemRoot", system_root, MAX_PATH);
  std::wstring msiexec = (n > 0 && n < MAX_PATH)
                             ? (std::wstring(system_root) + L"\\System32\\msiexec.exe")
                             : L"C:\\Windows\\System32\\msiexec.exe";

  std::wstring params = L"/i \"" + msi_path + L"\" /passive /norestart";
  SHELLEXECUTEINFOW sei{};
  sei.cbSize = sizeof(sei);
  sei.fMask = SEE_MASK_NOCLOSEPROCESS;
  sei.lpVerb = L"runas";
  sei.lpFile = msiexec.c_str();
  sei.lpParameters = params.c_str();
  sei.nShow = SW_SHOW;

  if (!ShellExecuteExW(&sei)) {
    LogLine(L"msiexec launch failed");
    return 1223;
  }
  if (sei.hProcess == nullptr) {
    LogLine(L"msiexec process was null");
    return 1;
  }
  WaitForSingleObject(sei.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(sei.hProcess, &code);
  CloseHandle(sei.hProcess);
  LogLine(L"msiexec exited code=" + std::to_wstring(code));
  return static_cast<int>(code);
}

bool MsiexecSucceeded(int code) {
  // 0 = success; 3010 = success, reboot required (we still relaunch the app).
  return code == 0 || code == 3010;
}

std::wstring DefaultExeBesideHelper() {
  wchar_t module[MAX_PATH];
  const DWORD n = GetModuleFileNameW(nullptr, module, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return {};
  std::wstring path(module, n);
  const size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return {};
  return path.substr(0, slash + 1) + L"dacx.exe";
}

void RelaunchDacx(const std::wstring& exe_path) {
  if (exe_path.empty()) {
    LogLine(L"relaunch skipped: empty exe path");
    return;
  }
  if (GetFileAttributesW(exe_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    LogLine(L"relaunch target missing: " + exe_path);
    return;
  }

  SHELLEXECUTEINFOW sei{};
  sei.cbSize = sizeof(sei);
  sei.fMask = SEE_MASK_FLAG_NO_UI;
  sei.lpVerb = L"open";
  sei.lpFile = exe_path.c_str();
  sei.nShow = SW_SHOWNORMAL;

  if (!ShellExecuteExW(&sei)) {
    LogLine(L"relaunch failed err=" + std::to_wstring(GetLastError()) +
            L" path=" + exe_path);
    return;
  }
  LogLine(L"relaunched " + exe_path);
}

struct Args {
  DWORD pid = 0;
  std::wstring msi;
  std::wstring sha256;
  std::wstring thumbprint;
  std::wstring publisher;
  std::wstring exe;
  bool relaunch = true;
};

bool ParseArgs(int argc, wchar_t** argv, Args* out) {
  for (int i = 1; i < argc; ++i) {
    const std::wstring key = argv[i];
    if (i + 1 >= argc) return false;
    const std::wstring value = argv[++i];
    if (key == L"--pid") {
      out->pid = static_cast<DWORD>(_wtoi(value.c_str()));
    } else if (key == L"--msi") {
      out->msi = value;
    } else if (key == L"--sha256") {
      out->sha256 = value;
      for (auto& c : out->sha256) {
        if (c >= L'A' && c <= L'F') c = static_cast<wchar_t>(c - L'A' + L'a');
      }
    } else if (key == L"--thumbprint") {
      out->thumbprint = NormalizeThumbprint(value);
    } else if (key == L"--publisher") {
      out->publisher = value;
    } else if (key == L"--exe") {
      out->exe = value;
    } else if (key == L"--relaunch") {
      out->relaunch = value != L"0" && value != L"false" && value != L"False";
    } else {
      return false;
    }
  }
  if (out->pid == 0 || out->msi.empty() || out->sha256.size() != 64) {
    return false;
  }
  for (wchar_t c : out->sha256) {
    if (!((c >= L'0' && c <= L'9') || (c >= L'a' && c <= L'f'))) return false;
  }
  return true;
}

int Run(int argc, wchar_t** argv) {
  Args args;
  if (!ParseArgs(argc, argv, &args)) {
    LogLine(L"bad arguments");
    return 13;
  }

  LogLine(L"started pid=" + std::to_wstring(args.pid) + L" msi=" + args.msi +
          L" publisher=" + args.publisher + L" thumb=" + args.thumbprint +
          L" sha=" + args.sha256 +
          L" relaunch=" + (args.relaunch ? L"1" : L"0"));

  const int wait_rc = WaitForPid(args.pid);
  if (wait_rc != 0) return wait_rc;

  LogLine(L"dacx exited, verifying sha256");
  std::wstring actual;
  if (!Sha256File(args.msi, &actual)) {
    LogLine(L"sha256 compute failed");
    return 12;
  }
  if (_wcsicmp(actual.c_str(), args.sha256.c_str()) != 0) {
    LogLine(L"sha256 mismatch expected=" + args.sha256 + L" actual=" + actual);
    return 12;
  }

  if (!args.thumbprint.empty() || !args.publisher.empty()) {
    int auth_rc = 0;
    if (!VerifyAuthenticode(args.msi, args.thumbprint, args.publisher,
                            &auth_rc)) {
      return auth_rc;
    }
  }

  LogLine(L"launching msiexec");
  const int msi_rc = LaunchMsiexec(args.msi);
  if (args.relaunch && MsiexecSucceeded(msi_rc)) {
    std::wstring exe = args.exe;
    if (exe.empty()) exe = DefaultExeBesideHelper();
    RelaunchDacx(exe);
  }
  return msi_rc;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) return 99;
  int rc = 99;
  try {
    rc = Run(argc, argv);
  } catch (...) {
    LogLine(L"fatal unhandled exception");
    rc = 99;
  }
  LocalFree(argv);
  return rc;
}
