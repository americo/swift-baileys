import SwiftProtobuf

extension ReceivedMessageContentParser {
	static func aiRichResponseContent(
		_ response: Proto_AIRichResponseMessage
	) -> ReceivedAIRichResponseContent {
		ReceivedAIRichResponseContent(
			messageType: response.hasMessageType ? aiRichResponseMessageType(response.messageType) : nil,
			submessages: response.submessages.map(aiRichResponseSubMessageContent),
			unifiedResponseData: response.hasUnifiedResponse && response.unifiedResponse.hasData
				? response.unifiedResponse.data
				: nil,
			serializedBytes: try? response.serializedData()
		)
	}

	private static func aiRichResponseSubMessageContent(
		_ submessage: Proto_AIRichResponseSubMessage
	) -> ReceivedAIRichResponseSubMessageContent {
		ReceivedAIRichResponseSubMessageContent(
			type: submessage.hasMessageType ? aiRichResponseSubMessageType(submessage.messageType) : nil,
			text: submessage.hasMessageText ? submessage.messageText : nil
		)
	}

	private static func aiRichResponseMessageType(
		_ type: Proto_AIRichResponseMessageType
	) -> ReceivedAIRichResponseMessageType {
		switch type {
		case .aiRichResponseTypeUnknown:
			.unknown
		case .aiRichResponseTypeStandard:
			.standard
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func aiRichResponseSubMessageType(
		_ type: Proto_AIRichResponseSubMessageType
	) -> ReceivedAIRichResponseSubMessageType {
		switch type {
		case .aiRichResponseUnknown:
			.unknown
		case .aiRichResponseGridImage:
			.gridImage
		case .aiRichResponseText:
			.text
		case .aiRichResponseInlineImage:
			.inlineImage
		case .aiRichResponseTable:
			.table
		case .aiRichResponseCode:
			.code
		case .aiRichResponseDynamic:
			.dynamic
		case .aiRichResponseMap:
			.map
		case .aiRichResponseLatex:
			.latex
		case .aiRichResponseContentItems:
			.contentItems
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
