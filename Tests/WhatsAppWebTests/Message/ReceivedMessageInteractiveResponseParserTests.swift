import Testing
@testable import WhatsAppWeb

@Suite("Received message interactive response parser")
struct ReceivedMessageInteractiveResponseParserTests {
	@Test("parses buttons response messages")
	func parsesButtonsResponseMessages() throws {
		var response = Proto_Message.ButtonsResponseMessage()
		response.selectedButtonID = "confirm"
		response.selectedDisplayText = "Confirm"
		response.type = .displayText
		var message = Proto_Message()
		message.buttonsResponseMessage = response

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .buttonsResponse(ReceivedButtonsResponseContent(
			selectedButtonID: "confirm",
			selectedDisplayText: "Confirm",
			type: .displayText
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses list response messages")
	func parsesListResponseMessages() throws {
		var reply = Proto_Message.ListResponseMessage.SingleSelectReply()
		reply.selectedRowID = "delivery"
		var response = Proto_Message.ListResponseMessage()
		response.title = "Delivery"
		response.listType = .singleSelect
		response.singleSelectReply = reply
		response.description_p = "Send it to my address"
		var message = Proto_Message()
		message.listResponseMessage = response

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .listResponse(ReceivedListResponseContent(
			title: "Delivery",
			listType: .singleSelect,
			selectedRowID: "delivery",
			description: "Send it to my address"
		)))
	}

	@Test("parses interactive native flow response messages")
	func parsesInteractiveNativeFlowResponseMessages() throws {
		var body = Proto_Message.InteractiveResponseMessage.Body()
		body.text = "Submitted"
		body.format = .extensions1
		var nativeFlow = Proto_Message.InteractiveResponseMessage.NativeFlowResponseMessage()
		nativeFlow.name = "single_select"
		nativeFlow.paramsJson = #"{"selected":"delivery"}"#
		nativeFlow.version = 3
		var response = Proto_Message.InteractiveResponseMessage()
		response.body = body
		response.nativeFlowResponseMessage = nativeFlow
		var message = Proto_Message()
		message.interactiveResponseMessage = response

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .interactiveResponse(ReceivedInteractiveResponseContent(
			body: ReceivedInteractiveResponseBodyContent(
				text: "Submitted",
				format: .extensions1
			),
			nativeFlowResponse: ReceivedNativeFlowResponseContent(
				name: "single_select",
				paramsJSON: #"{"selected":"delivery"}"#,
				version: 3
			)
		)))
	}

	@Test("parses template button reply messages")
	func parsesTemplateButtonReplyMessages() throws {
		var response = Proto_Message.TemplateButtonReplyMessage()
		response.selectedID = "ship_now"
		response.selectedDisplayText = "Ship now"
		response.selectedIndex = 2
		response.selectedCarouselCardIndex = 4
		var message = Proto_Message()
		message.templateButtonReplyMessage = response

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .templateButtonReply(ReceivedTemplateButtonReplyContent(
			selectedID: "ship_now",
			selectedDisplayText: "Ship now",
			selectedIndex: 2,
			selectedCarouselCardIndex: 4
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("preserves absent optional response fields")
	func preservesAbsentOptionalResponseFields() throws {
		var message = Proto_Message()
		message.buttonsResponseMessage = Proto_Message.ButtonsResponseMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .buttonsResponse(ReceivedButtonsResponseContent(
			selectedButtonID: nil,
			selectedDisplayText: nil,
			type: nil
		)))
	}
}
