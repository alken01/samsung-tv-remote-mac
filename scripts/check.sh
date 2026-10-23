#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
# XCTest is not shipped with the installed standalone Command Line Tools.
# Compile the production protocol/session sources directly into this small runner.
swiftc -parse-as-library \
    Sources/SamsungMenuRemote/Protocol.swift \
    Sources/SamsungMenuRemote/Discovery.swift \
    Sources/SamsungMenuRemote/Storage.swift \
    Sources/SamsungMenuRemote/Remote.swift \
    Tests/SamsungMenuRemoteTests/Checks.swift \
    -o .local/checks
.local/checks
