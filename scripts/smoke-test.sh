#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
BIN="${TMPDIR:-/tmp/}CopioSmokeTest-$$"
trap 'rm -f "$BIN"' EXIT
swiftc -parse-as-library -o "$BIN" \
  Sources/Copio/Models/Models.swift \
  Sources/Copio/Models/AppSettings.swift \
  Sources/Copio/Models/ClipArchive.swift \
  Sources/Copio/Persistence/Database.swift \
  Sources/Copio/Services/ClipboardServices.swift \
  Sources/Copio/Services/KeychainService.swift \
  Sources/Copio/Services/NotificationService.swift \
  Sources/Copio/App/AppModel.swift \
  Sources/Copio/Views/SearchBrowser.swift \
  scripts/SmokeTest.swift \
  -lsqlite3 -framework AppKit -framework Security -framework LocalAuthentication -framework ServiceManagement -framework UserNotifications
"$BIN"
