# Baileys TypeScript to Swift API Parity Matrix

This matrix tracks the socket methods exported by the TypeScript Baileys sockets against the Swift port. It is intentionally evidence-based: each row names the Swift owner that currently proves coverage or marks a remaining gap.

Status:
- Covered: Swift exposes an equivalent public API and has tests or roadmap evidence.
- Partial: Swift has useful support, but the TypeScript contract has options or behavior not fully matched.
- Pending: no current Swift equivalent found.
- Internal: TypeScript exposes internals that Swift intentionally keeps behind configured dependencies or lower-level APIs.

## Socket Core

| TypeScript API | Swift status | Evidence |
|---|---:|---|
| `query` | Covered | `WhatsAppClient.query(...)` in `Sources/WhatsAppWeb/WhatsAppClient.swift` |
| `sendNode` | Covered | public `WhatsAppClient.sendNode(...)` in `Sources/WhatsAppWeb/WhatsAppClient.swift` |
| `logout`, `end` | Covered | lifecycle/logout tests in `Tests/WhatsAppWebTests/Socket/WhatsAppClientLogoutTests.swift` |
| `requestPairingCode` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+PairingCode.swift` |
| `uploadPreKeys`, `uploadPreKeysToServerIfRequired` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+PreKeys.swift` |
| `executeUSyncQuery` | Covered | USync-backed profile/chat APIs in `Sources/WhatsAppWeb/WhatsAppClient+ChatQueries.swift` |
| `sendRawMessage`, `waitForSocketOpen`, `waitForMessage`, `sendUnifiedSession` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+SocketCoreAliases.swift` |
| `updateServerTimeOffset` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+ServerTime.swift` |
| `digestKeyBundle`, `rotateSignedPreKey` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+PreKeys.swift` |
| `authState`, `signalRepository`, `ws`, `ev`, `wamBuffer` | Internal | Swift exposes typed dependencies/events rather than TS mutable socket internals |

## Message Send And Receive

| TypeScript API | Swift status | Evidence |
|---|---:|---|
| `sendMessage` | Covered | typed send APIs in `Sources/WhatsAppWeb/WhatsAppClient+Messages.swift` and related message files |
| `relayMessage` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+MessageRelay.swift`; public overload accepts serialized WAProto, participant retry sends, `statusJidList` status fanout, and user-device cache option forwarding |
| `createParticipantNodes` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+ParticipantNodes.swift` |
| `getUSyncDevices` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+MessageDevices.swift` |
| `assertSessions` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+SignalSessions.swift` |
| `sendReceipt`, `sendReceipts`, `readMessages` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+PresenceReceipts.swift` |
| `refreshMediaConn`, `getMediaHost`, `waUploadToServer` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+MediaConnection.swift` |
| `updateMediaMessage` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+MediaRetry.swift` |
| `sendMessageAck`, `sendRetryRequest` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+StanzaAck.swift`, `Sources/WhatsAppWeb/WhatsAppClient+RetryRequests.swift` |
| `fetchMessageHistory`, `requestPlaceholderResend` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+PeerDataOperations.swift` |
| `rejectCall` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Calls.swift` |
| `updateMemberLabel` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+MemberLabels.swift` |
| `userDevicesCache`, `devicesMutex`, `messageRetryManager` | Internal | Swift keeps these as configured dependencies/internal state |

## Chats, Profile, Privacy, App State

| TypeScript API | Swift status | Evidence |
|---|---:|---|
| privacy update/fetch APIs | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Profile.swift` |
| `profilePictureUrl`, profile picture/name/status updates | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Profile.swift` |
| `fetchStatus`, `fetchDisappearingDuration`, `getBotListV2`, `onWhatsApp`, `pnFromLIDUSync` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+ChatQueries.swift` |
| `presenceSubscribe`, `sendPresenceUpdate` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+PresenceReceipts.swift` |
| `createCallLink` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Profile.swift` |
| `appPatch`, `chatModify`, `star`, labels, quick replies, contact wrappers | Covered | `Sources/WhatsAppWeb/WhatsAppClient+AppState.swift` |
| `resyncAppState` | Covered | `Sources/WhatsAppWeb/WhatsAppClient+AppStateSync.swift` |

## Groups, Communities, Business, Newsletter

| TypeScript API | Swift status | Evidence |
|---|---:|---|
| group metadata/create/leave/participants/settings/invites | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Groups.swift` |
| community metadata/create/link/unlink/participants/settings/invites | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Communities.swift` |
| business profile/catalog/products/order/cover photo | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Business.swift`, `Sources/WhatsAppWeb/WhatsAppClient+BusinessCoverPhoto.swift` |
| newsletter create/metadata/admin/follow/mute/picture/reaction/fetch/subscribe | Covered | `Sources/WhatsAppWeb/WhatsAppClient+Newsletters.swift` |

## Current Highest-Risk Remaining Gaps

1. The matrix is based on static source inspection plus the production-readiness and mock-e2e suites; it does not replace optional live WhatsApp compatibility validation.
2. `Docs/E2E_VALIDATION_CHECKLIST.md` records the automated high-fidelity mock coverage and the optional live-account pass criteria.
