import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Message reporting token builder")
struct MessageReportingTokenBuilderTests {
	@Test("builds Baileys-compatible reporting token node")
	func buildsBaileysCompatibleReportingTokenNode() throws {
		let secret = try Data(reportingHex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		var context = Proto_MessageContextInfo()
		context.messageSecret = secret
		var text = Proto_Message.ExtendedTextMessage()
		text.text = "hello reporting"
		text.matchedText = "https://example.com"
		text.description_p = "Desc"
		text.title = "Example"
		var message = Proto_Message()
		message.extendedTextMessage = text
		message.messageContextInfo = context

		let node = MessageReportingTokenBuilder.reportingNode(
			encodedMessage: try message.serializedData(),
			message: message,
			key: WhatsAppMessageKey(
				remoteJID: "222@s.whatsapp.net",
				fromMe: true,
				id: "3EB0REPORT",
				participant: "111@s.whatsapp.net"
			)
		)

		#expect(node == BinaryNode(
			tag: "reporting",
			content: .nodes([
				BinaryNode(
					tag: "reporting_token",
					attrs: ["v": "2"],
					content: .data(try Data(reportingHex: "a6a050635796e3c7f686b1054b70b51d"))
				)
			])
		))
	}

	@Test("skips reporting token for excluded modification messages")
	func skipsReportingTokenForExcludedModificationMessages() {
		var reaction = Proto_Message.ReactionMessage()
		reaction.text = "like"
		var reactionMessage = Proto_Message()
		reactionMessage.reactionMessage = reaction

		var pollUpdateMessage = Proto_Message()
		pollUpdateMessage.pollUpdateMessage = Proto_Message.PollUpdateMessage()

		#expect(!MessageReportingTokenBuilder.shouldIncludeReportingToken(reactionMessage))
		#expect(!MessageReportingTokenBuilder.shouldIncludeReportingToken(pollUpdateMessage))
	}

	@Test("returns nil when reporting inputs are incomplete")
	func returnsNilWhenReportingInputsAreIncomplete() throws {
		var plainMessage = Proto_Message()
		plainMessage.conversation = "Hello"
		#expect(MessageReportingTokenBuilder.reportingNode(
			encodedMessage: try plainMessage.serializedData(),
			message: plainMessage,
			key: reportingKey()
		) == nil)

		var context = Proto_MessageContextInfo()
		context.messageSecret = Data(repeating: 0x01, count: 32)
		var secretMessage = Proto_Message()
		secretMessage.conversation = "Hello"
		secretMessage.messageContextInfo = context
		#expect(MessageReportingTokenBuilder.reportingNode(
			encodedMessage: try secretMessage.serializedData(),
			message: secretMessage,
			key: reportingKey(id: "")
		) == nil)
	}
}

private func reportingKey(id: String? = "test-id") -> WhatsAppMessageKey {
	WhatsAppMessageKey(
		remoteJID: "123@s.whatsapp.net",
		fromMe: true,
		id: id
	)
}

private extension Data {
	init(reportingHex hexString: String) throws {
		var bytes: [UInt8] = []
		var index = hexString.startIndex

		while index < hexString.endIndex {
			let next = hexString.index(index, offsetBy: 2)
			guard let byte = UInt8(hexString[index..<next], radix: 16) else {
				throw MessageReportingTokenBuilderTestError.invalidHex
			}

			bytes.append(byte)
			index = next
		}

		self.init(bytes)
	}
}

private enum MessageReportingTokenBuilderTestError: Error {
	case invalidHex
}
