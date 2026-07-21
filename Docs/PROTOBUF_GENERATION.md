# WAProto Generation

`WAProto` must be generated from `Proto/WAProto.proto`. Do not translate or edit protobuf bindings by hand.

## Command

```bash
cd SwiftBaileys
bash Scripts/generate-wa-proto.sh
```

Use `--check` to verify that the generated Swift file is current without rewriting it:

```bash
cd SwiftBaileys
bash Scripts/generate-wa-proto.sh --check
```

## Requirements

- `protoc`
- `protoc-gen-swift` from `apple/swift-protobuf`

## Current Status

`protoc` and `protoc-gen-swift` are available locally. The generator script creates a sanitized copy under `.generated/WAProto.proto` because the upstream Baileys proto contains proto3 enums whose first value is not zero, which modern `protoc` rejects.

`WAProto.pb.swift` is generated output and is intentionally not hand-edited. It is currently a single large file because `protoc-gen-swift` emits one Swift file per `.proto` input. This mirrors the existing Baileys generated `WAProto/index.js` exception; hand-written Swift files remain under the 600-line limit.

SwiftProtobuf is resolved through the normal remote SwiftPM dependency:

```swift
.package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0")
```

## Other Generated Resources

Binary node tokens are stored as the bundled resource snapshot at `Sources/WhatsAppWeb/Resources/Binary/tokens.json`.
Verify its structural contract with:

```bash
node Scripts/verify-binary-token-resources.mjs
```

WAM definitions are stored as the bundled resource snapshot at `Sources/WhatsAppWeb/Resources/WAM/definitions.json`.
Verify its structural contract with:

```bash
node Scripts/verify-wam-definition-resources.mjs
```

The production-readiness gate runs all generated-resource checks to ensure `Sources/WhatsAppWeb/Generated/WAProto/WAProto.pb.swift`, `Sources/WhatsAppWeb/Resources/Binary/tokens.json`, and `Sources/WhatsAppWeb/Resources/WAM/definitions.json` are not stale.
