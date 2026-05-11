#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "mac-keychain-ssh.sh: skipping (not macOS)."
  exit 0
fi

KEYCHAIN_PATH="${KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
DOTENV_FILE="${DOTENV_FILE:-.env}"

dotenv_value() {
  local name="$1"
  [[ -f "$DOTENV_FILE" ]] || return 0
  awk -F= -v key="$name" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      val=substr($0, index($0, "=") + 1)
      sub(/\r$/, "", val)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      if ((val ~ /^".*"$/) || (val ~ /^'\''.*'\''$/)) {
        val=substr(val, 2, length(val)-2)
      }
      print val
    }
  ' "$DOTENV_FILE" | tail -n 1
}

if [[ -z "${KEYCHAIN_PASSWORD:-}" && -n "${SSH_USER_PWD:-}" ]]; then
  KEYCHAIN_PASSWORD="${SSH_USER_PWD}"
fi

if [[ -z "${KEYCHAIN_PASSWORD:-}" ]]; then
  KEYCHAIN_PASSWORD="$(dotenv_value KEYCHAIN_PASSWORD)"
fi

if [[ -z "${KEYCHAIN_PASSWORD:-}" ]]; then
  KEYCHAIN_PASSWORD="$(dotenv_value SSH_USER_PWD)"
fi

if [[ -z "${KEYCHAIN_PASSWORD:-}" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "Login keychain password: " KEYCHAIN_PASSWORD
    echo
  else
    echo "KEYCHAIN_PASSWORD or SSH_USER_PWD is required in non-interactive shells."
    exit 1
  fi
fi

echo "Preparing keychain for non-GUI codesign..."
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH"
security default-keychain -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "Keychain ready for SSH signing."
echo "Setup complete."
echo "Next: npm run release:mac"
exit 0
