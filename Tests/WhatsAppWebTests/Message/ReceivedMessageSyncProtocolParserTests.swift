import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Received message sync protocol parser")
struct ReceivedMessageSyncProtocolParserTests {
	@Test("parses app state sync key share protocol messages")
	func parsesAppStateSyncKeyShareProtocolMessages() throws {
		var keyID = Proto_Message.AppStateSyncKeyId()
		keyID.keyID = Data([0x01, 0x02, 0x03])
		var fingerprint = Proto_Message.AppStateSyncKeyFingerprint()
		fingerprint.rawID = 7
		fingerprint.currentIndex = 9
		fingerprint.deviceIndexes = [1, 4]
		var keyData = Proto_Message.AppStateSyncKeyData()
		keyData.keyData = Data([0x04, 0x05])
		keyData.fingerprint = fingerprint
		keyData.timestamp = 1_700_000_002
		var key = Proto_Message.AppStateSyncKey()
		key.keyID = keyID
		key.keyData = keyData
		var share = Proto_Message.AppStateSyncKeyShare()
		share.keys = [key]
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .appStateSyncKeyShare
		protocolMessage.appStateSyncKeyShare = share
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .appStateSyncKeyShare(ReceivedAppStateSyncKeyShareContent(keys: [
			ReceivedAppStateSyncKeyContent(
				keyID: Data([0x01, 0x02, 0x03]),
				keyIDBase64: "AQID",
				keyData: Data([0x04, 0x05]),
				fingerprint: ReceivedAppStateSyncKeyFingerprintContent(
					rawID: 7,
					currentIndex: 9,
					deviceIndexes: [1, 4]
				),
				timestamp: 1_700_000_002
			)
		])))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent app state sync key share fields")
	func preservesAbsentAppStateSyncKeyShareFields() throws {
		var share = Proto_Message.AppStateSyncKeyShare()
		share.keys = [Proto_Message.AppStateSyncKey()]
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .appStateSyncKeyShare
		protocolMessage.appStateSyncKeyShare = share
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .appStateSyncKeyShare(ReceivedAppStateSyncKeyShareContent(keys: [
			ReceivedAppStateSyncKeyContent(
				keyID: nil,
				keyIDBase64: nil,
				keyData: nil,
				fingerprint: nil,
				timestamp: nil
			)
		])))
	}

	@Test("parses app state sync key request protocol messages")
	func parsesAppStateSyncKeyRequestProtocolMessages() throws {
		var keyID = Proto_Message.AppStateSyncKeyId()
		keyID.keyID = Data([0x0a, 0x0b, 0x0c])
		var request = Proto_Message.AppStateSyncKeyRequest()
		request.keyIds = [keyID]
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .appStateSyncKeyRequest
		protocolMessage.appStateSyncKeyRequest = request
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .appStateSyncKeyRequest(ReceivedAppStateSyncKeyRequestContent(keyIDs: [
			ReceivedAppStateSyncKeyIDContent(
				keyID: Data([0x0a, 0x0b, 0x0c]),
				keyIDBase64: "CgsM"
			)
		])))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent app state sync key request ids")
	func preservesAbsentAppStateSyncKeyRequestIDs() throws {
		var request = Proto_Message.AppStateSyncKeyRequest()
		request.keyIds = [Proto_Message.AppStateSyncKeyId()]
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .appStateSyncKeyRequest
		protocolMessage.appStateSyncKeyRequest = request
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .appStateSyncKeyRequest(ReceivedAppStateSyncKeyRequestContent(keyIDs: [
			ReceivedAppStateSyncKeyIDContent(
				keyID: nil,
				keyIDBase64: nil
			)
		])))
	}

	@Test("parses LID migration mapping sync protocol messages")
	func parsesLIDMigrationMappingSyncProtocolMessages() throws {
		var assignedMapping = Proto_LIDMigrationMapping()
		assignedMapping.pn = 55_111
		assignedMapping.assignedLid = 99_222
		var latestMapping = Proto_LIDMigrationMapping()
		latestMapping.pn = 55_333
		latestMapping.assignedLid = 99_444
		latestMapping.latestLid = 99_555
		var payload = Proto_LIDMigrationMappingSyncPayload()
		payload.pnToLidMappings = [assignedMapping, latestMapping]
		payload.chatDbMigrationTimestamp = 1_700_000_003
		var sync = Proto_LIDMigrationMappingSyncMessage()
		sync.encodedMappingPayload = try payload.serializedData()
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .lidMigrationMappingSync
		protocolMessage.lidMigrationMappingSyncMessage = sync
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .lidMigrationMappingSync(ReceivedLIDMigrationMappingSyncContent(
			chatDBMigrationTimestamp: 1_700_000_003,
			mappings: [
				ReceivedLIDMigrationMappingContent(
					phoneNumber: "55111@s.whatsapp.net",
					lid: "99222@lid",
					rawPhoneNumber: 55_111,
					assignedLID: 99_222,
					latestLID: nil
				),
				ReceivedLIDMigrationMappingContent(
					phoneNumber: "55333@s.whatsapp.net",
					lid: "99555@lid",
					rawPhoneNumber: 55_333,
					assignedLID: 99_444,
					latestLID: 99_555
				)
			]
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("ignores undecodable LID migration mapping sync payloads")
	func ignoresUndecodableLIDMigrationMappingSyncPayloads() throws {
		var sync = Proto_LIDMigrationMappingSyncMessage()
		sync.encodedMappingPayload = Data([0xff])
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .lidMigrationMappingSync
		protocolMessage.lidMigrationMappingSyncMessage = sync
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .lidMigrationMappingSync(ReceivedLIDMigrationMappingSyncContent(
			chatDBMigrationTimestamp: nil,
			mappings: []
		)))
	}

	@Test("parses group member label change protocol messages")
	func parsesGroupMemberLabelChangeProtocolMessages() throws {
		var label = Proto_MemberLabel()
		label.label = "vip"
		label.labelTimestamp = 1_700_000_004
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .groupMemberLabelChange
		protocolMessage.memberLabel = label
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .groupMemberLabelChange(ReceivedGroupMemberLabelChangeContent(
			label: "vip",
			labelTimestamp: 1_700_000_004
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent group member label change fields")
	func preservesAbsentGroupMemberLabelChangeFields() throws {
		var protocolMessage = Proto_Message.ProtocolMessageMessage()
		protocolMessage.type = .groupMemberLabelChange
		var message = Proto_Message()
		message.protocolMessage = protocolMessage

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .groupMemberLabelChange(ReceivedGroupMemberLabelChangeContent(
			label: nil,
			labelTimestamp: nil
		)))
	}
}
