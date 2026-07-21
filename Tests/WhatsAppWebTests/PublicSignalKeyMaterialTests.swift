import Foundation
import Testing
import WhatsAppWeb

@Suite("Public Signal key material")
struct PublicSignalKeyMaterialTests {
	@Test("external consumers can derive raw Curve25519 keys from session bundles")
	func externalConsumersCanDeriveRawCurve25519KeysFromSessionBundles() {
		let bundle = SignalSessionBundle(
			jid: "123:0@s.whatsapp.net",
			registrationID: 1,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 2,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 3, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)

		#expect(bundle.identityCurve25519PublicKey == Data(repeating: 1, count: 32))
		#expect(bundle.signedPreKey.curve25519PublicKey == Data(repeating: 2, count: 32))
		#expect(bundle.preKey.curve25519PublicKey == Data(repeating: 4, count: 32))
	}

	@Test("invalid Signal public keys do not expose raw Curve25519 material")
	func invalidSignalPublicKeysDoNotExposeRawCurve25519Material() {
		#expect(SignalPreKey(keyID: 1, publicKey: Data(repeating: 1, count: 32)).curve25519PublicKey == nil)
		#expect(SignalPreKey(keyID: 1, publicKey: Data([4]) + Data(repeating: 1, count: 32)).curve25519PublicKey == nil)
	}

	@Test("external consumers can build native session install requests")
	func externalConsumersCanBuildNativeSessionInstallRequests() throws {
		let bundle = SignalSessionBundle(
			jid: "123:7@s.whatsapp.net",
			registrationID: 9,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 2,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 4, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)

		#expect(try bundle.nativeInstallRequest() == SignalSessionNativeInstallRequest(
			jid: "123:7@s.whatsapp.net",
			address: SignalProtocolAddress(name: "123", deviceID: 7),
			registrationID: 9,
			identityCurve25519PublicKey: Data(repeating: 1, count: 32),
			signedPreKeyID: 2,
			signedPreKeyCurve25519PublicKey: Data(repeating: 2, count: 32),
			signedPreKeySignature: Data(repeating: 3, count: 64),
			preKeyID: 4,
			preKeyCurve25519PublicKey: Data(repeating: 4, count: 32)
		))
	}

	@Test("external consumers can include local addresses in native session install requests")
	func externalConsumersCanIncludeLocalAddressesInNativeSessionInstallRequests() throws {
		let bundle = SignalSessionBundle(
			jid: "123:7@s.whatsapp.net",
			registrationID: 9,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 2,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 4, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)

		let request = try bundle.nativeInstallRequest(localJID: "999:0@s.whatsapp.net")

		#expect(request.localJID == "999:0@s.whatsapp.net")
		#expect(request.localAddress == SignalProtocolAddress(name: "999", deviceID: 0))
	}

	@Test("native session installers receive validated install requests from bundle injection")
	func nativeSessionInstallersReceiveValidatedInstallRequestsFromBundleInjection() async throws {
		let installer = PublicNativeSessionInstaller()
		let bundle = SignalSessionBundle(
			jid: "123:7@s.whatsapp.net",
			registrationID: 9,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 2,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 4, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)

		try await installer.injectSession(bundle: bundle)

		#expect(await installer.requests.map(\.address) == [
			SignalProtocolAddress(name: "123", deviceID: 7)
		])
	}

	@Test("external consumers can build native pre-key upload requests from credentials")
	func externalConsumersCanBuildNativePreKeyUploadRequestsFromCredentials() throws {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			me: WhatsAppUser(id: "999:0@s.whatsapp.net"),
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		let request = try credentials.nativePreKeyUploadRequest(
			currentServerPreKeyCount: 2,
			requestedUploadCount: 5
		)

		#expect(request == SignalNativePreKeyUploadRequest(
			localJID: "999:0@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "999", deviceID: 0),
			currentServerPreKeyCount: 2,
			registrationID: 11,
			identityPrivateKey: Data([5]),
			identityCurve25519PublicKey: Data(repeating: 6, count: 32),
			signedPreKeyID: 10,
			signedPreKeyPrivateKey: Data([7]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 8, count: 32),
			signedPreKeySignature: Data(repeating: 9, count: 64),
			firstUnuploadedPreKeyID: 13,
			requestedUploadCount: 5
		))
		#expect(request.preKeyIDs == [13, 14, 15, 16, 17])
		#expect(request.nextPreKeyIDAfterUpload == 18)
	}

	@Test("native account material accepts raw local Curve25519 public keys")
	func nativeAccountMaterialAcceptsRawLocalCurve25519PublicKeys() throws {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		let keyMaterial = try credentials.nativeAccountKeyMaterial()

		#expect(keyMaterial.identityCurve25519PublicKey == Data(repeating: 6, count: 32))
		#expect(keyMaterial.signedPreKeyCurve25519PublicKey == Data(repeating: 8, count: 32))
	}

	@Test("native pre-key upload requests reject invalid requested counts")
	func nativePreKeyUploadRequestsRejectInvalidRequestedCounts() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativePreKeyUploadRequestError.invalidRequestedUploadCount) {
			try credentials.nativePreKeyUploadRequest(requestedUploadCount: 0)
		}
		#expect(throws: SignalNativePreKeyUploadRequestError.invalidRequestedUploadCount) {
			try credentials.nativePreKeyUploadRequest(requestedUploadCount: -1)
		}
	}

	@Test("native pre-key upload requests reject invalid paired local JIDs")
	func nativePreKeyUploadRequestsRejectInvalidPairedLocalJIDs() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			me: WhatsAppUser(id: "not-a-jid"),
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativePreKeyUploadRequestError.invalidLocalJID) {
			try credentials.nativePreKeyUploadRequest(requestedUploadCount: 5)
		}
	}

	@Test("manually constructed native pre-key upload requests expose safe empty ID plans")
	func manuallyConstructedNativePreKeyUploadRequestsExposeSafeEmptyIDPlans() {
		let request = SignalNativePreKeyUploadRequest(
			currentServerPreKeyCount: 0,
			registrationID: 11,
			identityPrivateKey: Data([5]),
			identityCurve25519PublicKey: Data(repeating: 6, count: 32),
			signedPreKeyID: 10,
			signedPreKeyPrivateKey: Data([7]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 8, count: 32),
			signedPreKeySignature: Data(repeating: 9, count: 64),
			firstUnuploadedPreKeyID: 13,
			requestedUploadCount: -5
		)

		#expect(request.preKeyIDs == [])
		#expect(request.nextPreKeyIDAfterUpload == 13)
		#expect(request.currentServerPreKeyCount == 0)
	}

	@Test("manually constructed native pre-key upload requests reject invalid pre-key ID ranges")
	func manuallyConstructedNativePreKeyUploadRequestsRejectInvalidPreKeyIDRanges() {
		let request = SignalNativePreKeyUploadRequest(
			currentServerPreKeyCount: 0,
			registrationID: 11,
			identityPrivateKey: Data([5]),
			identityCurve25519PublicKey: Data(repeating: 6, count: 32),
			signedPreKeyID: 10,
			signedPreKeyPrivateKey: Data([7]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 8, count: 32),
			signedPreKeySignature: Data(repeating: 9, count: 64),
			firstUnuploadedPreKeyID: 0xFF_FF_FF,
			requestedUploadCount: 2
		)

		#expect(throws: SignalNativePreKeyUploadRequestError.invalidKeyID) {
			try request.validate()
		}
	}

	@Test("external consumers can build native account key material from credentials")
	func externalConsumersCanBuildNativeAccountKeyMaterialFromCredentials() throws {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(try credentials.nativeAccountKeyMaterial() == SignalNativeAccountKeyMaterial(
			registrationID: 11,
			identityPrivateKey: Data([5]),
			identityCurve25519PublicKey: Data(repeating: 6, count: 32),
			signedPreKeyID: 10,
			signedPreKeyPrivateKey: Data([7]),
			signedPreKeyCurve25519PublicKey: Data(repeating: 8, count: 32),
			signedPreKeySignature: Data(repeating: 9, count: 64)
		))
	}

	@Test("external consumers can build native account import requests from paired credentials")
	func externalConsumersCanBuildNativeAccountImportRequestsFromPairedCredentials() throws {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			me: WhatsAppUser(id: "123:4@s.whatsapp.net"),
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: true
		)

		#expect(try credentials.nativeAccountImportRequest() == SignalNativeAccountImportRequest(
			localJID: "123:4@s.whatsapp.net",
			localAddress: SignalProtocolAddress(name: "123", deviceID: 4),
			keyMaterial: SignalNativeAccountKeyMaterial(
				registrationID: 11,
				identityPrivateKey: Data([5]),
				identityCurve25519PublicKey: Data(repeating: 6, count: 32),
				signedPreKeyID: 10,
				signedPreKeyPrivateKey: Data([7]),
				signedPreKeyCurve25519PublicKey: Data(repeating: 8, count: 32),
				signedPreKeySignature: Data(repeating: 9, count: 64)
			)
		))
	}

	@Test("native account import requests require a paired local user")
	func nativeAccountImportRequestsRequireAPairedLocalUser() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativeKeyMaterialError.missingLocalUser) {
			try credentials.nativeAccountImportRequest()
		}
	}

	@Test("native account import requests reject invalid local JIDs")
	func nativeAccountImportRequestsRejectInvalidLocalJIDs() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(
				privateKey: Data([5]),
				publicKey: Data([5]) + Data(repeating: 6, count: 32)
			),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(
					privateKey: Data([7]),
					publicKey: Data([5]) + Data(repeating: 8, count: 32)
				),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			me: WhatsAppUser(id: "not-a-jid"),
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: true
		)

		#expect(throws: SignalNativeKeyMaterialError.invalidLocalJID) {
			try credentials.nativeAccountImportRequest()
		}
	}

	@Test("native pre-key upload requests reject invalid credential key material")
	func nativePreKeyUploadRequestsRejectInvalidCredentialKeyMaterial() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data(repeating: 6, count: 31)),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([5]) + Data(repeating: 8, count: 32)),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativePreKeyUploadRequestError.invalidKeyMaterial) {
			try credentials.nativePreKeyUploadRequest(requestedUploadCount: 5)
		}
	}

	@Test("native pre-key upload requests reject invalid credential signed pre-key IDs")
	func nativePreKeyUploadRequestsRejectInvalidCredentialSignedPreKeyIDs() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([5]) + Data(repeating: 6, count: 32)),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([5]) + Data(repeating: 8, count: 32)),
				signature: Data(repeating: 9, count: 64),
				keyID: 0
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativePreKeyUploadRequestError.invalidKeyID) {
			try credentials.nativePreKeyUploadRequest(requestedUploadCount: 5)
		}
	}

	@Test("native pre-key upload requests reject invalid credential pre-key ID ranges")
	func nativePreKeyUploadRequestsRejectInvalidCredentialPreKeyIDRanges() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([5]) + Data(repeating: 6, count: 32)),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([5]) + Data(repeating: 8, count: 32)),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 0,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativePreKeyUploadRequestError.invalidKeyID) {
			try credentials.nativePreKeyUploadRequest(requestedUploadCount: 5)
		}
	}

	@Test("native account key material rejects invalid credential key material")
	func nativeAccountKeyMaterialRejectsInvalidCredentialKeyMaterial() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data(repeating: 6, count: 31)),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([5]) + Data(repeating: 8, count: 32)),
				signature: Data(repeating: 9, count: 64),
				keyID: 10
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativeKeyMaterialError.invalidKeyMaterial) {
			try credentials.nativeAccountKeyMaterial()
		}
	}

	@Test("native account key material rejects invalid credential signed pre-key IDs")
	func nativeAccountKeyMaterialRejectsInvalidCredentialSignedPreKeyIDs() {
		let credentials = AuthenticationCredentials(
			noiseKey: AuthenticationKeyPair(privateKey: Data([1]), publicKey: Data([2])),
			pairingEphemeralKeyPair: AuthenticationKeyPair(privateKey: Data([3]), publicKey: Data([4])),
			signedIdentityKey: AuthenticationKeyPair(privateKey: Data([5]), publicKey: Data([5]) + Data(repeating: 6, count: 32)),
			signedPreKey: SignedAuthenticationKeyPair(
				keyPair: AuthenticationKeyPair(privateKey: Data([7]), publicKey: Data([5]) + Data(repeating: 8, count: 32)),
				signature: Data(repeating: 9, count: 64),
				keyID: 0x01_00_00_00
			),
			registrationID: 11,
			advSecretKey: "secret",
			nextPreKeyID: 12,
			firstUnuploadedPreKeyID: 13,
			accountSyncCounter: 0,
			registered: false
		)

		#expect(throws: SignalNativeKeyMaterialError.invalidKeyID) {
			try credentials.nativeAccountKeyMaterial()
		}
	}
}

private actor PublicNativeSessionInstaller: SignalNativeSessionInstalling {
	private(set) var requests: [SignalSessionNativeInstallRequest] = []

	func installSession(_ request: SignalSessionNativeInstallRequest) async throws {
		requests.append(request)
	}
}
