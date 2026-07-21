import Testing
@testable import WhatsAppWeb

@Suite("Received message buttons parser")
struct ReceivedMessageButtonsParserTests {
	@Test("parses buttons messages")
	func parsesButtonsMessages() throws {
		var firstText = Proto_Message.ButtonsMessage.Button.ButtonText()
		firstText.displayText = "Confirm"
		var firstButton = Proto_Message.ButtonsMessage.Button()
		firstButton.buttonID = "confirm"
		firstButton.buttonText = firstText
		firstButton.type = .response
		var flowText = Proto_Message.ButtonsMessage.Button.ButtonText()
		flowText.displayText = "Open form"
		var flowInfo = Proto_Message.ButtonsMessage.Button.NativeFlowInfo()
		flowInfo.name = "single_select"
		flowInfo.paramsJson = #"{"screen":"shipping"}"#
		var flowButton = Proto_Message.ButtonsMessage.Button()
		flowButton.buttonID = "shipping"
		flowButton.buttonText = flowText
		flowButton.type = .nativeFlow
		flowButton.nativeFlowInfo = flowInfo
		var buttons = Proto_Message.ButtonsMessage()
		buttons.contentText = "Choose an action"
		buttons.footerText = "Order #123"
		buttons.buttons = [firstButton, flowButton]
		buttons.headerType = .text
		buttons.text = "Order actions"
		var message = Proto_Message()
		message.buttonsMessage = buttons

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .buttons(ReceivedButtonsContent(
			contentText: "Choose an action",
			footerText: "Order #123",
			buttons: [
				ReceivedButtonContent(
					buttonID: "confirm",
					displayText: "Confirm",
					type: .response,
					nativeFlowInfo: nil
				),
				ReceivedButtonContent(
					buttonID: "shipping",
					displayText: "Open form",
					type: .nativeFlow,
					nativeFlowInfo: ReceivedButtonNativeFlowInfoContent(
						name: "single_select",
						paramsJSON: #"{"screen":"shipping"}"#
					)
				)
			],
			headerType: .text,
			header: .text("Order actions")
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional button fields")
	func preservesAbsentOptionalButtonFields() throws {
		var button = Proto_Message.ButtonsMessage.Button()
		button.buttonID = "empty"
		var buttons = Proto_Message.ButtonsMessage()
		buttons.buttons = [button]
		var message = Proto_Message()
		message.buttonsMessage = buttons

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .buttons(ReceivedButtonsContent(
			contentText: nil,
			footerText: nil,
			buttons: [
				ReceivedButtonContent(
					buttonID: "empty",
					displayText: nil,
					type: nil,
					nativeFlowInfo: nil
				)
			],
			headerType: nil,
			header: nil
		)))
	}
}
