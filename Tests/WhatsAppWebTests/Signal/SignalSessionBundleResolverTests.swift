import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Signal session bundle resolver")
struct SignalSessionBundleResolverTests {
	@Test("queries encrypt key bundles and parses session material")
	func queriesEncryptKeyBundlesAndParsesSessionMaterial() async throws {
		let query = RecordingSignalBundleQuery(response: bundleResponse())
		let resolver = SignalSessionBundleResolver(
			query: query.query(_:timeout:),
			idGenerator: { "bundle-1" }
		)

		let bundles = try await resolver.fetchBundles(for: ["123:0@s.whatsapp.net", "456:2@s.whatsapp.net"])

		#expect(
			await query.requests == [
				BinaryNode(
					tag: "iq",
					attrs: ["id": "bundle-1", "xmlns": "encrypt", "type": "get", "to": "@s.whatsapp.net"],
					content: .nodes([
						BinaryNode(
							tag: "key",
							content: .nodes([
								BinaryNode(tag: "user", attrs: ["jid": "123:0@s.whatsapp.net"]),
								BinaryNode(tag: "user", attrs: ["jid": "456:2@s.whatsapp.net"])
							])
						)
					])
				)
			]
		)
		#expect(bundles == [
			SignalSessionBundle(
				jid: "123:0@s.whatsapp.net",
				registrationID: 7,
				identityKey: Data([5]) + Data(repeating: 1, count: 32),
				signedPreKey: SignalPreKey(
					keyID: 1,
					publicKey: Data([5]) + Data(repeating: 2, count: 32),
					signature: Data(repeating: 7, count: 64)
				),
				preKey: SignalPreKey(
					keyID: 2,
					publicKey: Data([5]) + Data(repeating: 3, count: 32),
					signature: nil
				)
			)
		])
		#expect(bundles.first?.address == SignalProtocolAddress(name: "123", deviceID: 0))
	}

	@Test("adds identity reason when forced")
	func addsIdentityReasonWhenForced() async throws {
		let query = RecordingSignalBundleQuery(response: bundleResponse())
		let resolver = SignalSessionBundleResolver(query: query.query(_:timeout:), idGenerator: { "bundle-2" })

		_ = try await resolver.fetchBundles(for: ["123:0@s.whatsapp.net"], force: true)

		let request = await query.requests[0]
		let user = request.firstChild(named: "key")?.firstChild(named: "user")
		#expect(user?.attrs["reason"] == "identity")
	}

	@Test("rejects invalid bundle request inputs before query")
	func rejectsInvalidBundleRequestInputsBeforeQuery() async {
		let query = RecordingSignalBundleQuery(response: bundleResponse())
		let resolver = SignalSessionBundleResolver(query: query.query(_:timeout:), idGenerator: { "" })

		await #expect(throws: SignalSessionBundleResolverError.emptyRequestID) {
			try await resolver.fetchBundles(for: ["123:0@s.whatsapp.net"])
		}
		#expect(await query.requests.isEmpty)

		#expect(throws: SignalSessionBundleResolverError.emptyJIDs) {
			try SignalSessionBundleResolver.makeRequest(for: [], id: "bundle-3")
		}
		#expect(throws: SignalSessionBundleResolverError.invalidJID("not-a-jid")) {
			try SignalSessionBundleResolver.makeRequest(for: ["not-a-jid"], id: "bundle-4")
		}
	}

	@Test("rejects malformed public key lengths")
	func rejectsMalformedPublicKeyLengths() throws {
		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(from: bundleResponse(identity: Data([1, 2, 3])))
		}

		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(from: bundleResponse(signedPreKey: Data([4, 5, 6])))
		}

		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(from: bundleResponse(preKey: Data([9, 10])))
		}
	}

	@Test("rejects prefixed public keys with an invalid version byte")
	func rejectsPrefixedPublicKeysWithAnInvalidVersionByte() throws {
		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(
				from: bundleResponse(identity: Data([4]) + Data(repeating: 1, count: 32))
			)
		}

		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(
				from: bundleResponse(signedPreKey: Data([4]) + Data(repeating: 2, count: 32))
			)
		}

		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(
				from: bundleResponse(preKey: Data([4]) + Data(repeating: 3, count: 32))
			)
		}
	}

	@Test("rejects signed pre-key signatures with invalid length")
	func rejectsSignedPreKeySignaturesWithInvalidLength() throws {
		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(from: bundleResponse(signature: Data([7, 8])))
		}
	}

	@Test("rejects native install requests with invalid key IDs")
	func rejectsNativeInstallRequestsWithInvalidKeyIDs() {
		let bundle = SignalSessionBundle(
			jid: "123:7@s.whatsapp.net",
			registrationID: 9,
			identityKey: Data([5]) + Data(repeating: 1, count: 32),
			signedPreKey: SignalPreKey(
				keyID: 0,
				publicKey: Data([5]) + Data(repeating: 2, count: 32),
				signature: Data(repeating: 3, count: 64)
			),
			preKey: SignalPreKey(keyID: 4, publicKey: Data([5]) + Data(repeating: 4, count: 32))
		)

		#expect(throws: SignalSessionBundleValidationError.invalidKeyID) {
			try bundle.nativeInstallRequest()
		}
	}

	@Test("rejects bundles with invalid Signal addresses")
	func rejectsBundlesWithInvalidSignalAddresses() throws {
		#expect(throws: SignalSessionBundleResolverError.invalidBundle) {
			try SignalSessionBundleResolver.parseBundles(from: bundleResponse(jid: "not-a-jid"))
		}
	}

	private func bundleResponse(
		jid: String = "123:0@s.whatsapp.net",
		identity: Data = Data(repeating: 1, count: 32),
		signedPreKey: Data = Data(repeating: 2, count: 32),
		preKey: Data = Data(repeating: 3, count: 32),
		signature: Data = Data(repeating: 7, count: 64)
	) -> BinaryNode {
		BinaryNode(
			tag: "iq",
			attrs: ["type": "result"],
			content: .nodes([
				BinaryNode(
					tag: "list",
					content: .nodes([
						BinaryNode(
							tag: "user",
							attrs: ["jid": jid],
							content: .nodes([
								BinaryNode(
									tag: "skey",
									content: .nodes([
										BinaryNode(tag: "id", content: .data(Data([0, 0, 1]))),
										BinaryNode(tag: "value", content: .data(signedPreKey)),
										BinaryNode(tag: "signature", content: .data(signature))
									])
								),
								BinaryNode(
									tag: "key",
									content: .nodes([
										BinaryNode(tag: "id", content: .data(Data([0, 0, 2]))),
										BinaryNode(tag: "value", content: .data(preKey))
									])
								),
								BinaryNode(tag: "identity", content: .data(identity)),
								BinaryNode(tag: "registration", content: .data(Data([0, 0, 0, 7])))
							])
						)
					])
				)
			])
		)
	}
}

private actor RecordingSignalBundleQuery {
	private let response: BinaryNode
	private(set) var requests: [BinaryNode] = []

	init(response: BinaryNode) {
		self.response = response
	}

	func query(_ node: BinaryNode, timeout: Duration) async throws -> BinaryNode {
		#expect(timeout == .seconds(60))
		requests.append(node)
		return response
	}
}
