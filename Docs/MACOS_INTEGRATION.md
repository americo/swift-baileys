# SwiftBaileys macOS Integration

This package is a macOS-only Swift rewrite of the Baileys WhatsApp Web client. It exposes protocol-safe Swift APIs for auth persistence, socket lifecycle, message send/receive, media, device discovery, and Signal session preparation.

The package does not ship a full native libsignal session backend yet. Production apps must provide a `WhatsAppNativeSignalBackend`, or compose a `WhatsAppNativeSignalStore` with a `WhatsAppNativeSignalCryptoProvider` through `WhatsAppNativeSignalBackendAdapter`, backed by a real Signal implementation. `WhatsAppNativeSignalRuntime` wraps that backend as the package's native Signal adapter.

The package ships `WhatsAppNativeSignalRuntime`, a public bootstrap helper that wraps an app-owned `WhatsAppNativeSignalBackend`, or a `WhatsAppNativeSignalStore` plus `WhatsAppNativeSignalCryptoProvider`, as `WhatsAppNativeSignalAdapter`, creates file-backed auth state, configures the media uploader, and wires the client message dependencies. The compile-checked adapter shell in `Examples/NativeSignalBridgeExample/main.swift` shows the recommended production boundary, including account import, session-check, and pre-key upload state that a native store usually owns. The returned runtime keeps both the client and adapter available, so after pairing succeeds and `me.id` is present the app can call `ensureReadyForMessaging(...)`, pass client events through `handleEvent(_:)`, keep `startReadinessMonitor()` alive, or await `runReadinessMonitor()` to validate message dependencies and idempotently import the local Signal account on `.credentialsUpdated`. The example intentionally delegates cryptographic operations to a native backend protocol instead of shipping placeholder Signal crypto.

## Package Setup

Add the `WhatsAppWeb` library product from `SwiftBaileys/Package.swift` to the macOS target:

```swift
.package(path: "SwiftBaileys")
```

Then depend on:

```swift
.product(name: "WhatsAppWeb", package: "SwiftBaileys")
```

The package depends on SwiftProtobuf through the normal remote SwiftPM package declaration, so a macOS app can resolve it without a local `.deps` checkout.

## Auth State

Use `FileAuthenticationStore` for durable macOS auth state. It stores Baileys-compatible `creds.json` plus Signal key files in the selected directory, restricts the auth directory to `0700`, and restricts credential/key files to `0600`.

```swift
import Foundation
import WhatsAppWeb

let authDirectory = URL(fileURLWithPath: "/path/to/app-support/auth")
let store = AppNativeSignalStore()
let cryptoProvider = AppNativeSignalCryptoProvider()
let runtime = try await WhatsAppNativeSignalRuntime.make(
	authDirectory: authDirectory,
	store: store,
	cryptoProvider: cryptoProvider,
	ensureReadyForMessagingOnLoad: true
)
let client = runtime.client
```

Do not commit or upload this directory. It contains long-lived WhatsApp and Signal credentials.
For new credentials, pass an `AuthenticationCredentialsFactory` configured with `SignalSignedPreKeySigning` so the native libsignal backend signs the Baileys signed pre-key payload (`0x05` plus the raw signed pre-key public key). The factory rejects generated Curve25519 keypairs unless both private and public keys are 32 bytes, rejects ADV secret random output unless it is 32 bytes, and rejects signed-pre-key signatures unless they are 64 bytes. Apps can call `try signedPreKeySigner.assertReadyForCredentialSigning()` to run the same side-effect-light ephemeral signing preflight before enabling pairing. `WhatsAppNativeSignalAdapter` includes that signing boundary, so one native adapter can own auth signing, account identity import, encryption, decryption, session installation, session checks, and pre-key upload. The older closure-based signer initializer remains available for tests and small adapters.

After credentials are paired and contain `me.id`, call `try await runtime.ensureReadyForMessaging()` to validate message dependencies and import the local Signal address, original local JID, identity key pair, registration id, and signed pre-key into the app-owned native store if needed. Pass `ensureReadyForMessagingOnLoad: true` to `WhatsAppNativeSignalRuntime.make(...)` when the app should perform that same idempotent check immediately after loading already-paired credentials on relaunch; the option is skipped while credentials are still unpaired. The underlying client helper builds and returns `SignalNativeAccountImportRequest`, and fails with `WhatsAppClientError.missingAuthenticationState`, `SignalNativeKeyMaterialError.missingLocalUser`, `.invalidLocalJID`, `.invalidKeyID`, or `.invalidKeyMaterial` before the native backend receives an unusable identity. Manually constructed account import/check requests are also rejected when `localJID` does not map to `localAddress`. If the native store can check whether the account is already present, implement `SignalNativeAccountImportChecking` and use `try await client.importNativeSignalAccountIfNeeded(using: signalStore)` for relaunch-safe idempotent bootstrap. `try await signalAdapter.importAccount(credentials: authState.credentials)` remains available when the app wants to import directly from an `AuthenticationState` it owns outside the runtime.

Apps can let the runtime watch the client's stream:

```swift
let readinessTask = runtime.startReadinessMonitor()
```

Keep the task for the client lifetime and cancel it during shutdown. If the app wants the runtime to retain the task, call `await runtime.startManagedReadinessMonitor()` after setup, inspect `await runtime.managedReadinessMonitorStatus()` for `.running`, `.completed`, or `.failed(<error type>)`, and call `await runtime.stopManagedReadinessMonitor()` during shutdown. Apps that already own their event task can call `try await runtime.runReadinessMonitor()` directly. The monitor checks already-paired loaded credentials before waiting for new events, then keeps watching `.credentialsUpdated` so relaunch and fresh-pairing flows use the same import/readiness path. The monitor intentionally throws readiness/import errors instead of swallowing them, so the app can decide whether to retry, surface setup UI, or disconnect.

## Signal Backend Boundary

The app owns the native Signal backend. Apps can either implement `WhatsAppNativeSignalBackend` directly, or keep storage and crypto separate with `WhatsAppNativeSignalStore` for account/session/pre-key state and `WhatsAppNativeSignalCryptoProvider` for the `LibSignalClient` calls:

```swift
import Foundation
import WhatsAppWeb

let store = AppNativeSignalStore()
let cryptoProvider = AppNativeSignalCryptoProvider()
let signalAdapter = WhatsAppNativeSignalBackendAdapter(
	store: store,
	cryptoProvider: cryptoProvider
)
```

Implement these native boundaries in the app layer. Their methods receive validated `SignalProtocolAddress`, `SignalSessionNativeInstallRequest`, `WhatsAppNativeDirectMessage`, `WhatsAppNativeGroupMessage`, and pre-key upload DTOs, so the native backend can call libsignal without reparsing WhatsApp JIDs. Account import and account-presence checks receive `WhatsAppNativeSignalAccount.localJID` alongside the validated local Signal address for stores that index by the original WhatsApp identity. Session-existence checks receive `SignalSessionAddressCheck` values with both the original device JID and the validated Signal address, then return the addresses that already have native sessions. For a native libsignal-backed app, prefer this composed adapter path when persistent Signal state and `LibSignalClient` calls live in different objects. `WhatsAppComposedNativeSignalBackend` remains available when the app wants to hold the composed backend directly before wrapping it with `WhatsAppNativeSignalBackendAdapter(backend:)`. Then wire the adapter with `WhatsAppClientMessageDependencies(nativeSignalAdapter:query:)`; SwiftBaileys will use `SignalSessionAddressChecking` for session existence, convert fetched bundles into `SignalSessionNativeInstallRequest` values through `SignalNativeSessionInstalling`, and call `SignalPreKeyUploading` when WhatsApp reports low pre-key counts. Native adapters can still implement the addressed request methods directly, while SwiftBaileys provides the string-based protocol bridge used by the socket internals.
`assertReadyForSignalOperations()` is the native Signal startup preflight exposed through `SignalNativeOperationReadinessChecking`, `WhatsAppNativeSignalAdapter`, and `WhatsAppNativeSignalBackend`. `SignalSignedPreKeySigning.assertReadyForCredentialSigning()` separately proves that the backend can sign an ephemeral Baileys signed-pre-key payload and rejects non-64-byte signatures. `WhatsAppNativeSignalRuntime.make(...)` calls both checks before loading or creating auth state. The app should validate that the native libsignal bridge is loaded, required stores are reachable, and cryptographic operations can fail fast with a useful setup error. Keep these checks side-effect-light; account import still happens later through `ensureReadyForMessaging(...)` or the readiness monitor.
`NativeSignalBridgeExample.makeBackendSkeleton()` returns a compile-checked composed backend shell with in-memory account import, session-check, session-install, and pre-key upload state. Its storage code conforms to `WhatsAppNativeSignalStore` and stays separate from `WhatsAppNativeSignalCryptoProvider`, so a macOS app can keep the shell shape and inject a provider backed by `LibSignalClient` for credential signing, direct/group encryption, incoming decryption, and sender-key distribution processing. Without that provider, those cryptographic methods still throw `backendRequired`. `swift run NativeSignalBridgeExample --self-test` verifies both the storage shell and provider delegation without pretending to provide Signal cryptography.

`EncryptedMessage.type` should match the direct Signal ciphertext kind sent to WhatsApp, such as `msg` or `pkmsg`; prefer `EncryptedMessage(ciphertextType:ciphertext:)` when the native backend can return a `SignalDirectCiphertextType`. Group sends use `EncryptedGroupMessage`: SwiftBaileys wraps `senderKeyDistributionMessage` into a WAProto sender-key distribution message for direct device fanout, then sends the group ciphertext as `enc type=skmsg`. The relay builder rejects empty direct ciphertext, empty group ciphertext, and empty sender-key distribution bytes when distribution fanout is required, so custom encryptors cannot accidentally emit malformed `enc` nodes.
For outgoing messages, `SignalDirectMessageEncryptionRequest` and `SignalGroupMessageEncryptionRequest` expose validated Signal addresses before the app calls the native libsignal backend. When the client has `authState.credentials.me.id`, direct encryption requests also include `localJID` and `localAddress`, so native adapters can call `LibSignalClient.signalEncrypt(...)` without reparsing the local identity. Both request initializers reject empty plaintext with `SignalMessageEncryptionRequestValidationError.emptyMessageData`. `WhatsAppNativeDirectMessage` preserves the original remote `jid`, optional `localJID`, validated remote address, and optional local address for app-owned storage or logging. `WhatsAppNativeGroupMessage` preserves the `groupJID`, original `senderJID`, validated sender address, and plaintext bytes for Sender Key encryption. `AuthenticationCredentialsFactory` and `WhatsAppNativeSignalBackendAdapter` reject invalid signed-pre-key signatures before SwiftBaileys persists credentials, while the adapter also rejects empty direct ciphertext, group ciphertext, and sender-key distribution bytes returned by the native backend before relay assembly. If a native adapter is configured before pairing finishes, SwiftBaileys reads the current local identity again at send/decrypt/session-install time after credentials are updated. `MessageEncrypting` and `GroupMessageEncrypting` provide extension methods that accept these request types, so existing adapters can keep implementing the string-based protocol methods while new app code uses typed validation consistently with incoming decryption. `WhatsAppNativeSignalAdapter` goes the other direction too: implement the request-based methods and the package will bridge string-based calls into validated requests.
Use `SignalProtocolAddress.validated(jid:)` when bridging WhatsApp device JIDs into the native Signal backend so Baileys-compatible Signal names are derived consistently while invalid JIDs fail with `SignalProtocolAddressValidationError.invalidJID`. Normal WhatsApp and legacy `c.us` addresses become the bare user id, LID/hosted addresses append the Baileys domain type suffix, and `storageKey` exposes the `name.deviceID` key used for session records. The optional `SignalProtocolAddress(jid:)` initializer remains available for non-throwing checks.
For fetched key bundles, `SignalSessionBundle.address` exposes the same normalized address so session injection does not need to parse `bundle.jid` again.
`SignalSessionBundle.validatedAddress()` returns the normalized Signal address or throws `SignalSessionBundleValidationError.invalidAddress` / `.invalidKeyMaterial`. `hasValidSignalKeyMaterial` is also public when an adapter wants a non-throwing preflight. SwiftBaileys applies the same validation before its own session-injection paths.
`SignalSessionBundle.identityKey` and `SignalPreKey.publicKey` keep the Baileys/libsignal serialized Signal public-key format (`0x05` plus 32 bytes). Use `identityCurve25519PublicKey` and `curve25519PublicKey` when a native backend needs the raw 32-byte Curve25519 key material.
Use `SignalSessionBundle.nativeInstallRequest(localJID:)` when adapting a fetched bundle into a native libsignal `PreKeyBundle`: it returns the normalized remote `SignalProtocolAddress`, optional validated local address, registration id, key ids, raw Curve25519 public keys, and signed pre-key signature after the same address, key material, and 3-byte key-id validation SwiftBaileys uses before injection. Apps can implement `SignalNativeSessionInstalling.installSession(_:)`; its default `injectSession(bundle:)` bridge calls `nativeInstallRequest()` before handing the request to the app. `WhatsAppNativeSignalBackendAdapter` also validates manually constructed `SignalSessionNativeInstallRequest` key material, key ids, and remote/local JID-to-address consistency before backend delegation. `WhatsAppNativeSignalSession` exposes those same install fields directly, while preserving the original request, so a backend can map the DTO into its libsignal storage without reparsing the request envelope. When `configureNativeSignalAdapter(...)` is used, SwiftBaileys passes the current `authState.credentials.me.id` through session preparation so native installers receive `localJID` and `localAddress` alongside the remote bundle, including after pairing updates credentials.
If your native session store is keyed by Signal addresses rather than WhatsApp JID strings, implement `SignalSessionAddressChecking` and build `SignalSessionPreparer(addressChecker:bundleResolver:sessionInjector:)`. SwiftBaileys will pass `SignalSessionAddressCheck` values containing both the original device JID and the normalized `SignalProtocolAddress`, then map existing addresses back to the JID fetch policy internally.
`SignalSessionPreparer.assertSessions(for:force:)` rejects invalid requested JIDs with `SignalSessionPreparationError.invalidJID(...)` before checking local sessions or fetching bundles. That keeps native Signal stores and network fetches from receiving values that cannot map to a Signal protocol address.
For incoming messages, `SignalDirectMessageDecryptionRequest`, `SignalGroupMessageDecryptionRequest`, and `SenderKeyDistributionMessageRequest` expose validated `SignalProtocolAddress` values before the app calls the native libsignal backend. `SignalDirectMessageDecryptionRequest.ciphertextType` maps WhatsApp `enc type=msg` to `.signalMessage` for `LibSignalClient.signalDecrypt(...)`, and `enc type=pkmsg` to `.preKeySignalMessage` for `LibSignalClient.signalDecryptPreKey(...)`; when auth state is available the request also carries `localAddress` for the local `toAddress` / `localAddress` parameter. Direct and group decrypt request initializers reject empty ciphertext with `SignalMessageDecryptionRequestValidationError.emptyCiphertext`. `WhatsAppNativeDirectCiphertextMessage` preserves the original remote `jid`, optional `localJID`, validated addresses, ciphertext type, and ciphertext bytes. `WhatsAppNativeGroupCiphertextMessage` preserves the group JID plus original author JID and validated author address; `WhatsAppNativeSenderKeyDistributionMessage` preserves the sender-key author JID, optional group JID, validated author address, serialized WAProto distribution envelope, and optional raw `axolotlSenderKeyDistributionMessage` bytes for native libsignal processing. Empty incoming direct or group ciphertext fails before reaching the native Signal backend and emits `.emptyCiphertext`; unsupported direct types fail before reaching the adapter and emit `.unsupportedDirectCiphertextType(...)`; empty sender-key distribution payloads fail while building `SenderKeyDistributionMessageRequest` with `.emptySenderKeyDistributionMessage`. `SignalMessageDecrypting` also provides extension methods that accept these request types, so existing adapters can keep implementing the string-based protocol methods while app code uses the typed request objects for validation and logging. Native adapters can implement the request-based decrypt and sender-key-distribution methods directly.
When using `WhatsAppNativeSignalBackendAdapter`, empty plaintext returned by direct or group decrypt is rejected as `.emptyDirectPlaintext` or `.emptyGroupPlaintext` before SwiftBaileys attempts WAProto parsing. Treat those as native backend failures rather than valid empty WhatsApp messages.
After loading or creating auth state, call `AuthenticationCredentials.nativeAccountKeyMaterial()` if your native Signal backend needs to import the current account identity and signed pre-key immediately. It returns the registration id, identity private key, raw identity public key, signed pre-key id, signed pre-key private key, raw signed pre-key public key, and signed pre-key signature after the same validation used by low-pre-key recovery, including the 3-byte signed-pre-key id range.
If your native Signal backend owns pre-key generation and upload state, provide a `SignalPreKeyUploading` implementation through `WhatsAppClientMessageDependencies(preKeyUploader:)` or `WhatsAppNativeSignalAdapter`. SwiftBaileys will call it with `SignalPreKeyUploadRequest(currentCount:requestedUploadCount:nativeUploadRequest:)` when WhatsApp reports a low server-side pre-key count, instead of using the package's generic file-backed pre-key path. Apps can also call `getAvailablePreKeysOnServer(requestID:)` to run the same Baileys-compatible server count query explicitly, or call `uploadPreKeysToServerIfRequired(requestID:)` during startup to mirror Baileys' full refill policy: initial 812-key upload when the server has none, 5-key refill at the minimum threshold, and refill when the current local pre-key is missing from the key store. When the client has authentication state, `nativeUploadRequest` contains optional `localJID` and `localAddress` when `me.id` is available, plus the server-reported `currentServerPreKeyCount`, registration id, identity private key, raw identity public key, signed pre-key id, signed pre-key private key, raw signed pre-key public key, signed pre-key signature, first unuploaded pre-key id, requested count, `preKeyIDs`, and `nextPreKeyIDAfterUpload` for app-owned libsignal upload planning; without authentication state it remains `nil`. `AuthenticationCredentials.nativePreKeyUploadRequest(currentServerPreKeyCount:requestedUploadCount:)` rejects non-positive counts with `SignalNativePreKeyUploadRequestError.invalidRequestedUploadCount`, invalid credential signed-pre-key ids or generated pre-key id ranges with `.invalidKeyID`, and invalid paired local JIDs with `.invalidLocalJID`; manually constructed native requests expose an empty `preKeyIDs` plan for non-positive counts, while `WhatsAppNativeSignalBackendAdapter` still validates local JID/address consistency, raw public-key material, signed-pre-key signatures, signed-pre-key ids, and generated pre-key id ranges before handing the upload to the app-owned backend. Plain `PreKeyUploading` remains available for integrations that only need the requested count. Failed low-count recovery emits `.preKeyUploadFailed(PreKeyUploadFailure)` after `.preKeyCountUpdated`, including the current count, requested upload count, a typed `failureReason`, and the string `reason` for logging so the app can surface or retry the failure.

The official `signalapp/libsignal` Swift binding is CocoaPods-oriented for consuming apps; its SwiftPM manifest is documented upstream as a local-development convenience, not a supported package dependency. Keep that backend in the app layer and bridge it through `WhatsAppNativeSignalBackend` rather than adding an unstable package dependency to SwiftBaileys.

## Client Wiring

Prefer the runtime helper for app startup:

```swift
let runtime = try await WhatsAppNativeSignalRuntime.make(
	authDirectory: authDirectory,
	store: store,
	cryptoProvider: cryptoProvider,
	ensureReadyForMessagingOnLoad: true
)
let client = runtime.client
```

If the app implements storage and crypto in one object, pass that object as `backend:` instead.

When manual wiring is needed, create the client with auth state first. Then build message dependencies with the client's `query` method so SwiftBaileys owns USync device discovery and Signal bundle fetching. Configure dependencies before connecting so device discovery and Signal bundle queries can use the same socket owner. `configureNativeSignalAdapter(_:mediaUploader:)` uses the client's own `query` path by default; pass an explicit `query:` only in tests or specialized integrations.
After pairing succeeds and `.credentialsUpdated` contains the local user, import the local account into the native Signal store:

```swift
_ = try await runtime.ensureReadyForMessaging()
```

For stores that can check existing imported accounts, use:

```swift
let importResult = try await client.importNativeSignalAccountIfNeeded(using: signalStore)
```

When startup should only verify that the native Signal account is already imported, use `try await client.assertNativeSignalAccountImported(using: signalStore)`. It returns the validated `SignalNativeAccountImportRequest` on success and throws `WhatsAppClientNativeSignalAccountError.missingImportedAccount(...)` when the native store is not ready.

For a single startup gate that checks message dependencies, native Signal operation readiness, credential signing, and local native account import, call `try await client.assertNativeMessageReadiness(capabilities:using:)` with your `WhatsAppNativeSignalAdapter` before enabling send/decrypt flows. When startup should also import the account if it is missing, use `try await client.ensureNativeMessageReadiness(capabilities:using:)`; it validates message dependencies, runs `assertReadyForSignalOperations()`, asks the adapter to sign an ephemeral signed-pre-key payload, then performs the same idempotent account import as `importNativeSignalAccountIfNeeded(using:)`. The older `accountChecker:` overload remains available for integrations that only need to verify a separate account store.

When startup needs a side-effect-light health check, use `try await client.nativeMessageReadinessReport(capabilities:using:)` with the native adapter. The report includes the validated local `SignalNativeAccountImportRequest`, typed `signalOperationsReadiness` (`.ready`, `.failed(String)`, or `.notChecked`), typed `credentialSigningReadiness` (`.ready`, `.failed(String)`, or `.notChecked`), typed `nativeAccountReadiness` (`.imported`, `.missing`, or `.failed(String)`), compatibility fields such as `isSignalOperationsReady`, `signalOperationsReadinessFailure`, `isNativeAccountImported`, and `nativeAccountReadinessFailure`, the requested capability set, currently available capabilities, and the missing dependency map for the requested capabilities. `failures` exposes those blockers as typed values so app startup code can gate UI without reinterpreting every report field. It never imports account material, but the native-adapter overload signs an ephemeral signed-pre-key payload to prove credential signing before the app enables pairing or relaunch flows; call `ensureNativeMessageReadiness(capabilities:using:)` when the app should repair a missing local account. Existing wrappers that initialize the report with the older `isSignalOperationsReady`, `signalOperationsReadinessFailure`, and `isNativeAccountImported` parameters continue to compile, but new code should prefer the typed readiness states to avoid ambiguous startup diagnostics. The `accountChecker:` overload remains available for account-store-only diagnostics, but it cannot verify native Signal operation readiness or credential signing and reports `.notChecked`.

Before exposing send/decrypt flows in your macOS app, inspect readiness with `availableMessageCapabilities()` and `missingMessageDependencies()`. `availableMessageCapabilities()` returns the capabilities that are ready to use, which is useful for enabling UI or feature gates. `missingMessageDependencies()` returns a capability-keyed map of the exact missing public dependencies for `.directSend`, `.groupSend`, `.mediaSend`, `.incomingDecrypt`, `.preKeyUpload`, and `.retryResend`, so the app can fail early during startup instead of discovering configuration errors during the first user action. Use `missingMessageDependencies(for:)` when a feature-specific check is more useful than the aggregate startup report.
Use `try client.assertMessageCapabilities(...)` when startup should fail hard unless a required capability set is ready. It throws `WhatsAppClientMessageDependencyError` with the same capability-keyed dependency map, so app logs and setup UI can report the exact missing native Signal, media, auth, or session boundary.
When showing a forward action for received messages, check `received.content.isForwardable` before calling `sendForwardedMessage(...)`. It matches the public forward send path and stays `false` for internal sync/stub content that still returns `WhatsAppClientForwardMessageError.unsupportedContent`.

## Connect And Pair

```swift
let runtime = try await NativeSignalBridgeExample.makeRuntime(
	authDirectory: authDirectory,
	backend: nativeSignalBackend,
	ensureReadyForMessagingOnLoad: true
)
let client = runtime.client

try await client.connect()

for await event in client.events {
	if let importResult = try await runtime.handleEvent(event) {
		print("Native Signal account ready; imported:", importResult.imported)
	}

	switch event {
	case .qrCode(let code):
		print("Scan this QR code:", code)
	case .connected(let user):
		print("Connected as", user)
	case .disconnected(let reason):
		print("Disconnected", reason)
	case .receivedMessage(let message):
		print("Received", message)
	case .messageDecryptionFailed(let failure):
		print("Could not decrypt", failure.id ?? "<missing id>", failure.reason)
	case .messageRetryRequested(let request):
		print("Retry requested for", request.messageIDs, "by", request.requesterJID)
	case .messageRetryResendFailed(let failure):
		print("Automatic retry resend failed", failure.request.messageIDs, failure.reason)
	default:
		break
	}
}
```

Credential updates emitted by `.credentialsUpdated` are already persisted when `AuthenticationState` was created through `loadOrCreate(store:credentialsFactory:)`.
If the initial `connect()` call fails, SwiftBaileys closes the attempted transport, restores `.disconnected`, and rethrows the original transport error so the app can retry without a stuck `.connecting` state.
The receive loop emits `.disconnected` when the WebSocket closes, when WhatsApp sends stream termination nodes, and when frame receiving or decoding fails. Treat this event as the app's reconnect trigger rather than assuming a connected client is still receiving frames. Pending `query` calls fail immediately with `WhatsAppClientError.disconnected(reason:)` when the client disconnects, so app tasks do not wait for the normal IQ timeout after the socket is already gone.
Decryption failures are emitted as `.messageDecryptionFailed(MessageDecryptionFailure)` with safe stanza metadata: message id, sender, participant, timestamp, ciphertext type, and a typed reason. Malformed Signal addresses, invalid group sender-key stanzas, and invalid message padding use dedicated reason cases; unknown backend failures still use `.decryptionError(...)`. SwiftBaileys does not acknowledge messages that fail decryption, so the app can log, inspect Signal session state, or wait for WhatsApp retry flow without falsely marking the message as processed.

## Contact Queries

Use `onWhatsApp(_:)` to check phone numbers or PN JIDs through WhatsApp USync contact lookup. LID inputs are skipped before the request because they are not phone-number contact queries. Server responses marked `type=in` return `exists: true`; responses marked `type=out` return `exists: false`, so the app can distinguish absent accounts from inputs that were not sent.

## Sending Text

```swift
let messageID = try await client.sendTextMessage(
	to: "123456789@s.whatsapp.net",
	content: OutgoingTextContent(
		text: "@alice hello from SwiftBaileys",
		mentions: ["111111111@s.whatsapp.net"],
		mentionAll: true,
		isForwarded: true,
		forwardingScore: 3,
		quoted: OutgoingQuotedTextContent(
			chatJID: "123456789@s.whatsapp.net",
			messageID: "3EB0QUOTED",
			participantJID: "111111111@s.whatsapp.net",
			text: "original text"
		)
	)
)
```

The parameter-style overload remains available when that is more convenient:

```swift
let messageID = try await client.sendTextMessage(
	to: "123456789@s.whatsapp.net",
	text: "@alice hello from SwiftBaileys",
	mentions: ["111111111@s.whatsapp.net"],
	mentionAll: true,
	isForwarded: true,
	forwardingScore: 3,
	quoted: OutgoingQuotedTextContent(
		chatJID: "123456789@s.whatsapp.net",
		messageID: "3EB0QUOTED",
		participantJID: "111111111@s.whatsapp.net",
		text: "original text"
	)
)
```

Text mentions are encoded as WAProto `contextInfo.mentionedJid`, matching Baileys' `mentions` option. `mentionAll` sets `contextInfo.nonJidMentions` to `1`, matching Baileys' all-mention marker. `isForwarded` and `forwardingScore` map to the matching `contextInfo` forwarding fields. `quoted` embeds a quoted text payload with `stanzaID`, `participant`, `quotedMessage`, and a `remoteJid` only when the quoted chat differs from the destination. `sendEditMessage(...)` accepts the same mention and forwarding parameters and stores them inside the edited text payload. For one-to-one chats, the send path resolves devices through USync, asks your `SignalSessionChecking` implementation which sessions already exist, fetches missing Signal bundles, injects sessions through your adapter, pads and encodes WAProto, encrypts per device, and sends the Baileys relay stanza. A complete `WhatsAppSignalAdapter` does not need to expose its native session state through `SignalKeyStore`; the older query-backed initializer with `signalKeys` remains available for adapters that still mirror session records into SwiftBaileys storage. For groups, SwiftBaileys fetches group metadata, resolves participant devices, prepares direct sessions for Sender Key distribution, calls `encryptGroupMessage(...)`, and sends the Baileys `skmsg` stanza. Media sends can use `WhatsAppMediaUploader(query:)` so media connection lookup and HTTP upload host fallback stay inside SwiftBaileys.
`URLSessionMediaDownloadTransport` and `URLSessionMediaUploadTransport` validate HTTP responses before returning data. Non-HTTP responses throw `.nonHTTPResponse`, and non-2xx HTTP responses throw `.httpStatus(statusCode, body)` so apps can surface or log CDN/upload failures instead of treating error pages as media bytes or silent upload misses. `WhatsAppMediaUploader` rejects empty encrypted upload data before fetching media hosts, and treats empty upload responses, empty returned media URL/direct path metadata, and per-host transport errors as reasons to try the next media host before failing the whole upload.
For incoming image, document, audio, video, sticker, invoice attachment, and payment-background messages, `mediaDownloadRequest()` prefers the absolute media URL when present and falls back to `https://mmg.whatsapp.net` plus `directPath` when the URL field is absent. `MediaDownloadRequest.validate()` rejects empty media keys and non-32-byte encrypted/plaintext SHA-256 values before network work. Downloads still validate encrypted and plaintext SHA-256 values before returning bytes.

## Peer Data Operations

Use `requestMessageHistory(count:oldestMessageKey:oldestMessageTimestampMilliseconds:)` to request on-demand history from the phone. SwiftBaileys wraps the request as a Baileys-compatible peer-data protocol message, relays it to the authenticated user's normalized JID with `category=peer` and `push_priority=high_force`, and keeps the `meta appdata=default` node required by the WhatsApp Web flow. The response arrives as a normal history-sync message, where `ReceivedHistorySyncNotificationContent.peerDataRequestSessionID` links the response back to peer-data handling.
Use `requestPlaceholderResend(for:)` when an incoming placeholder message needs the full message content from the phone. SwiftBaileys sends the Baileys-compatible placeholder resend peer-data request through the same encrypted relay path. When the receive path parses a `.placeholder` message, it acknowledges and emits the message, then attempts this resend request automatically if the client has auth and message-send dependencies configured. Matching responses are parsed as `.peerDataOperationRequestResponse`, with recovered messages in `placeholderResendMessages`.

## Retry Requests

When WhatsApp sends a `receipt type=retry`, SwiftBaileys emits `.messageRetryRequested(MessageRetryRequest)`, acknowledges the receipt stanza, and then attempts an automatic resend from its short in-memory recent-message cache. The event includes the original message key, all requested message ids, requester JID, retry count, timestamp, requester registration id, and any valid retry session bundle from the receipt. If automatic resend cannot run because integration dependencies, Signal session preparation, encryption, or transport sending fails, SwiftBaileys emits `.messageRetryResendFailed(MessageRetryResendFailure)` with the original retry request and a typed reason. Missing message dependencies are reported as `.missingDependency(...)`, required retry fields use dedicated cases, and unknown external failures still fall back to `.resendError(...)`. Apps can still call `resendCachedMessage(for:)` or `resendCachedMessages(for:)` manually when they want explicit retry control without touching generated protobuf types. If the retry receipt carries a session bundle and the client was configured with a `SignalSessionInjecting` dependency, SwiftBaileys injects that bundle directly before reencryption. Device-specific retry requests are encrypted only to the requesting participant and force Signal session preparation when no receipt bundle is available. If a group retry requester has no device suffix, SwiftBaileys resolves that requester's devices and sends retry stanzas with the group as `to` and each requester device as `participant`. Batch retry receipts resend every requested message id still present in the recent-message cache. `WhatsAppClientConfiguration.maxMessageRetryCount` limits repeated resends for the same destination, message id, and requester to avoid retry loops.

For manual retry handling, a received retry bundle can be converted through the same validated path SwiftBaileys uses internally:

```swift
if let retryBundle = request.sessionBundle {
	let installRequest = try retryBundle.nativeInstallRequest(for: request.requesterJID)
	try await signalAdapter.installSession(installRequest)
}
```

The conversion throws `MessageRetrySessionBundleValidationError.missingPreKey` when the receipt did not include an installable one-time pre-key, or `.invalidSessionBundle(...)` when the requester JID or Signal key material is invalid. `nativeInstallRequest(for:localJID:)` carries the optional validated local Signal address for native libsignal stores, and SwiftBaileys passes the current authenticated user JID when a retry receipt includes an installable bundle. `signalSessionBundle(for:)` remains available when an app wants the intermediate Baileys-compatible bundle instead of the native install request.

## Current Production Gap

The remaining critical production gap is the native Signal adapter. SwiftBaileys intentionally does not hand-roll Signal cryptography; it provides the public boundaries and verified WhatsApp protocol wiring so the app can connect a vetted Signal implementation.

## Production Completion Checklist

Use this checklist in the consuming macOS app, not inside SwiftBaileys:

- Implement `WhatsAppNativeSignalStore` with durable local-account, session, sender-key, and pre-key state backed by the chosen Signal store.
- Implement `WhatsAppNativeSignalCryptoProvider` with real libsignal calls for signed-pre-key signing, direct encryption/decryption, group sender-key encryption/decryption, and sender-key distribution processing.
- Create the runtime with `WhatsAppNativeSignalRuntime.make(authDirectory:store:cryptoProvider:ensureReadyForMessagingOnLoad:)` or the equivalent `backend:` overload.
- Run `try await runtime.ensureReadyForMessaging()` after pairing, and use `ensureReadyForMessagingOnLoad: true` for already-paired relaunches.
- Verify `try await client.assertNativeMessageReadiness(capabilities:using:)` before enabling message send/decrypt UI.
- Exercise live WhatsApp flows with the real backend: pair, send direct text, receive direct text, send group text, receive group text, send media, receive media, handle retry receipts, and recover from low-pre-key notifications.
- Keep `Scripts/verify-production-readiness.sh` green after any bridge changes; it remains the package-level gate, while the live WhatsApp checks are the app-level release gate.
