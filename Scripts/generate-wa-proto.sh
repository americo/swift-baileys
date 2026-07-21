#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROTO_FILE="$ROOT_DIR/Proto/WAProto.proto"
SANITIZED_PROTO_FILE="$ROOT_DIR/.generated/WAProto.proto"
OUTPUT_DIR="$ROOT_DIR/Sources/WhatsAppWeb/Generated/WAProto"
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
	CHECK_ONLY=true
elif [[ $# -gt 0 ]]; then
	echo "usage: $0 [--check]" >&2
	exit 1
fi

if ! command -v protoc >/dev/null 2>&1; then
	echo "error: protoc is required to generate WAProto Swift sources" >&2
	exit 1
fi

if ! command -v protoc-gen-swift >/dev/null 2>&1; then
	echo "error: protoc-gen-swift is required. Install it from apple/swift-protobuf, then rerun this script." >&2
	exit 1
fi

node "$ROOT_DIR/Scripts/sanitize-wa-proto-for-swift.mjs"

if [[ "$CHECK_ONLY" == true ]]; then
	TMP_DIR="$(mktemp -d)"
	trap 'rm -rf "$TMP_DIR"' EXIT
	protoc \
		--proto_path="$ROOT_DIR/.generated" \
		--swift_out="$TMP_DIR" \
		"$SANITIZED_PROTO_FILE"

	if ! cmp -s "$TMP_DIR/WAProto.pb.swift" "$OUTPUT_DIR/WAProto.pb.swift"; then
		echo "error: WAProto.pb.swift is stale; run Scripts/generate-wa-proto.sh" >&2
		exit 1
	fi
else
	mkdir -p "$OUTPUT_DIR"
	protoc \
		--proto_path="$ROOT_DIR/.generated" \
		--swift_out="$OUTPUT_DIR" \
		"$SANITIZED_PROTO_FILE"
fi
