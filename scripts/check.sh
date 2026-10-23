#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
# XCTest is not shipped with the installed standalone Command Line Tools.
# Compile the production protocol/session sources directly into this small runner.
swiftc -parse-as-library \
    Sources/SamsungTVRemote/Protocol.swift \
    Sources/SamsungTVRemote/Discovery.swift \
    Sources/SamsungTVRemote/Storage.swift \
    Sources/SamsungTVRemote/Remote.swift \
    Tests/SamsungTVRemoteTests/Checks.swift \
    -o .local/checks
.local/checks
