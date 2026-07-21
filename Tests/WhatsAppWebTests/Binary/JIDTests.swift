import Testing
@testable import WhatsAppWeb

@Suite("JID")
struct JIDTests {
	@Test("decodes phone user, device and server")
	func decodesPhoneUserDeviceAndServer() throws {
		let jid = try #require(JID("258840000000:42@s.whatsapp.net"))

		#expect(jid.user == "258840000000")
		#expect(jid.device == 42)
		#expect(jid.server == "s.whatsapp.net")
		#expect(jid.domainType == .whatsapp)
	}

	@Test("normalizes legacy c.us users to s.whatsapp.net")
	func normalizesLegacyUsers() throws {
		let jid = try #require(JID("16505361212@c.us"))

		#expect(jid.normalizedUser == "16505361212@s.whatsapp.net")
	}

	@Test("detects LID and hosted domain types from server")
	func detectsDomainTypes() throws {
		#expect(JID("123@lid")?.domainType == .lid)
		#expect(JID("123@hosted")?.domainType == .hosted)
		#expect(JID("123@hosted.lid")?.domainType == .hostedLid)
	}

	@Test("compares JIDs by user portion only")
	func comparesUsersOnly() {
		#expect(JID.areSameUser("258840000000:1@s.whatsapp.net", "258840000000@lid"))
		#expect(!JID.areSameUser("258840000000@s.whatsapp.net", "258850000000@s.whatsapp.net"))
	}

	@Test("transfers device from source to destination")
	func transfersDevice() {
		#expect(JID.transferDevice(from: "111:7@s.whatsapp.net", to: "222@lid") == "222:7@lid")
		#expect(JID.transferDevice(from: "111@s.whatsapp.net", to: "222@lid") == "222:0@lid")
	}

	@Test("builds Signal protocol address from device JIDs")
	func buildsSignalProtocolAddressFromDeviceJIDs() throws {
		#expect(SignalProtocolAddress(jid: "123:1@s.whatsapp.net") == SignalProtocolAddress(name: "123", deviceID: 1))
		#expect(SignalProtocolAddress(jid: "123@c.us") == SignalProtocolAddress(name: "123", deviceID: 0))
		#expect(SignalProtocolAddress(jid: "abc:9@lid") == SignalProtocolAddress(name: "abc_1", deviceID: 9))
		#expect(SignalProtocolAddress(jid: "abc:99@hosted") == SignalProtocolAddress(name: "abc_128", deviceID: 99))
		#expect(SignalProtocolAddress(jid: "not-a-jid") == nil)
		#expect(SignalProtocolAddress(jid: "123:bad@s.whatsapp.net") == nil)
	}

	@Test("builds Signal session storage keys")
	func buildsSignalSessionStorageKeys() throws {
		#expect(SignalProtocolAddress(jid: "123:1@s.whatsapp.net")?.storageKey == "123.1")
		#expect(SignalProtocolAddress(jid: "abc:9@lid")?.storageKey == "abc_1.9")
	}
}
