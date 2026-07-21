import Testing
@testable import WhatsAppWeb

@Suite("Message forward buttons content builder")
struct MessageForwardButtonsContentBuilderTests {
	@Test("forwards buttons messages by preserving button metadata")
	func forwardsButtonsMessagesByPreservingButtonMetadata() throws {
		var buttonText = Proto_Message.ButtonsMessage.Button.ButtonText()
		buttonText.displayText = "Open form"
		var nativeFlowInfo = Proto_Message.ButtonsMessage.Button.NativeFlowInfo()
		nativeFlowInfo.name = "single_select"
		nativeFlowInfo.paramsJson = #"{"screen":"shipping"}"#
		var button = Proto_Message.ButtonsMessage.Button()
		button.buttonID = "shipping"
		button.buttonText = buttonText
		button.type = .nativeFlow
		button.nativeFlowInfo = nativeFlowInfo
		var buttons = Proto_Message.ButtonsMessage()
		buttons.contentText = "Choose an action"
		buttons.footerText = "Order #123"
		buttons.headerType = .text
		buttons.text = "Order actions"
		buttons.buttons = [button]
		var source = Proto_Message()
		source.buttonsMessage = buttons

		let message = try MessageContentBuilder.forward(source, fromMe: false)

		#expect(message.hasButtonsMessage)
		#expect(message.buttonsMessage.contentText == "Choose an action")
		#expect(message.buttonsMessage.footerText == "Order #123")
		#expect(message.buttonsMessage.headerType == .text)
		#expect(message.buttonsMessage.text == "Order actions")
		#expect(message.buttonsMessage.buttons[0].buttonID == "shipping")
		#expect(message.buttonsMessage.buttons[0].buttonText.displayText == "Open form")
		#expect(message.buttonsMessage.buttons[0].nativeFlowInfo.paramsJson == #"{"screen":"shipping"}"#)
		#expect(message.buttonsMessage.contextInfo.isForwarded)
		#expect(message.buttonsMessage.contextInfo.forwardingScore == 1)
	}
}
