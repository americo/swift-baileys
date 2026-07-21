#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
	current_developer_dir="$(xcode-select -p 2>/dev/null || true)"
	if [[ "$current_developer_dir" == "/Library/Developer/CommandLineTools" &&
		! -e "$current_developer_dir/../SharedFrameworks/BuildServerProtocol.framework" ]]; then
		for candidate in \
			/Applications/Xcode.app/Contents/Developer \
			/Applications/Xcode-beta.app/Contents/Developer; do
			if [[ -x "$candidate/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" &&
				-e "$candidate/../SharedFrameworks/BuildServerProtocol.framework" ]]; then
				export DEVELOPER_DIR="$candidate"
				break
			fi
		done
	fi
fi

echo "==> Swift toolchain"
xcrun --find swift
swift --version

echo "==> Checking generated WAM definitions"
node Scripts/verify-wam-definition-resources.mjs

echo "==> Checking generated binary tokens"
node Scripts/verify-binary-token-resources.mjs

echo "==> Checking generated WAProto"
Scripts/generate-wa-proto.sh --check

echo "==> Building native Signal bridge example"
swift build --product NativeSignalBridgeExample

echo "==> Running native Signal bridge example self-test"
example_output="$(swift run NativeSignalBridgeExample --self-test)"
if [[ "$example_output" != "NativeSignalBridgeExample self-test passed." ]]; then
	echo "Unexpected native Signal bridge example output:"
	echo "$example_output"
	exit 1
fi

echo "==> Building SwiftBaileys"
swift build

echo "==> Running test suite"
swift test

echo "==> Running mock e2e validation"
Scripts/verify-mock-e2e.sh

echo "==> Checking manual Swift file sizes"
too_large_files="$(
	find Sources Tests Examples -name '*.swift' -not -path '*/Generated/*' -print0 |
		xargs -0 wc -l |
		awk '$2 != "total" && $1 > 600 { print $1 " " $2 }'
)"

if [[ -n "$too_large_files" ]]; then
	echo "Swift files over 600 lines:"
	echo "$too_large_files"
	exit 1
fi

echo "==> Largest manual Swift files"
find Sources Tests Examples -name '*.swift' -not -path '*/Generated/*' -print0 |
	xargs -0 wc -l |
	sort -nr |
	head -10

echo "SwiftBaileys production readiness checks passed."
