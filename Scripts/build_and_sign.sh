#!/usr/bin/env bash
#
# build_and_sign.sh — build Release di Onda e firma con certificato self-signed.
#
# Prerequisiti:
#   - Xcode installato (xcodebuild disponibile).
#   - Un certificato "Code Signing" self-signed creato in Keychain Access.
#     Imposta SIGN_IDENTITY col nome esatto del certificato.
#
# Uso:
#   SIGN_IDENTITY="Onda Self-Signed" ./Scripts/build_and_sign.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/dist"
APP_NAME="Onda"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

echo "==> Pulizia"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Build Release (SwiftPM)"
swift build -c release --package-path "${ROOT_DIR}"

BIN_PATH="$(swift build -c release --package-path "${ROOT_DIR}" --show-bin-path)/${APP_NAME}"

# NB: questo script produce per ora il solo eseguibile. Il packaging completo in
# .app bundle (Info.plist, entitlements, Resources) verra' aggiunto quando il
# progetto avra' la fase Xcode/xcodebuild. Vedi CLAUDE.md.
echo "==> Eseguibile prodotto: ${BIN_PATH}"
cp "${BIN_PATH}" "${BUILD_DIR}/${APP_NAME}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "==> Firma con identita': ${SIGN_IDENTITY}"
  codesign --force --options runtime --sign "${SIGN_IDENTITY}" "${BUILD_DIR}/${APP_NAME}"
  echo "==> Verifica firma"
  codesign --verify --verbose "${BUILD_DIR}/${APP_NAME}"
else
  echo "==> SIGN_IDENTITY non impostata: salto la firma."
  echo "    Esempio: SIGN_IDENTITY=\"Onda Self-Signed\" $0"
fi

echo "==> Fatto. Output in ${BUILD_DIR}"
