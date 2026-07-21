# SwiftBaileys

SwiftBaileys is a macOS-only Swift Package rewrite of the Baileys WhatsApp Web client. The library product is `WhatsAppWeb`.

It exposes Swift APIs for authentication persistence, WebSocket lifecycle, binary node encoding, Noise handshake/transport, WhatsApp message send/receive flows, media encryption/download/upload, group/newsletter/business operations, retry handling, and native Signal integration boundaries.

## Requirements

- macOS 13 or newer
- Swift 6 toolchain

## Verify

Run the production-readiness gate before using or changing the package:

```sh
Scripts/verify-production-readiness.sh
```

The script builds the native Signal bridge example, builds the package, runs the full test suite, and fails if any manual Swift file exceeds 600 lines.

## Native Signal Backend

SwiftBaileys does not bundle a full native libsignal session backend. Production apps must provide a real Signal implementation through `WhatsAppNativeSignalBackend`, or compose a `WhatsAppNativeSignalStore` with a `WhatsAppNativeSignalCryptoProvider` through `WhatsAppNativeSignalBackendAdapter`; `WhatsAppNativeSignalRuntime` wraps that backend as the package's native Signal adapter.

Use `WhatsAppNativeSignalRuntime.make(...)` to create the client, file-backed auth state, media uploader, and native Signal adapter from an app-owned Signal backend, or directly from a `WhatsAppNativeSignalStore` plus `WhatsAppNativeSignalCryptoProvider`. Apps can keep `runtime.startReadinessMonitor()` alive while the client runs, or await `runtime.runReadinessMonitor()`, to import the local Signal account after pairing credential updates. The compile-checked storage shell in `Examples/NativeSignalBridgeExample/main.swift` shows the recommended app boundary for account import, session checks, and pre-key upload state while delegating cryptographic methods to an injected provider that a real app can back with libsignal. See `Docs/MACOS_INTEGRATION.md` for the integration sequence and `Docs/PORTING_ROADMAP.md` for current parity evidence.
