public enum ReceivedButtonsHeaderType: Equatable, Sendable {
	case unknown
	case empty
	case text
	case document
	case image
	case video
	case location
	case unrecognized(Int)
}

public enum ReceivedButtonType: Equatable, Sendable {
	case unknown
	case response
	case nativeFlow
	case unrecognized(Int)
}

public enum ReceivedButtonsHeaderContent: Equatable, Sendable {
	case text(String)
	case document(ReceivedDocumentContent)
	case image(ReceivedImageContent)
	case video(ReceivedVideoContent)
	case location(ReceivedLocationContent)
}

public struct ReceivedButtonNativeFlowInfoContent: Equatable, Sendable {
	public let name: String?
	public let paramsJSON: String?

	public init(name: String?, paramsJSON: String?) {
		self.name = name
		self.paramsJSON = paramsJSON
	}
}

public struct ReceivedButtonContent: Equatable, Sendable {
	public let buttonID: String?
	public let displayText: String?
	public let type: ReceivedButtonType?
	public let nativeFlowInfo: ReceivedButtonNativeFlowInfoContent?

	public init(
		buttonID: String?,
		displayText: String?,
		type: ReceivedButtonType?,
		nativeFlowInfo: ReceivedButtonNativeFlowInfoContent?
	) {
		self.buttonID = buttonID
		self.displayText = displayText
		self.type = type
		self.nativeFlowInfo = nativeFlowInfo
	}
}

public struct ReceivedButtonsContent: Equatable, Sendable {
	public let contentText: String?
	public let footerText: String?
	public let buttons: [ReceivedButtonContent]
	public let headerType: ReceivedButtonsHeaderType?
	public let header: ReceivedButtonsHeaderContent?

	public init(
		contentText: String?,
		footerText: String?,
		buttons: [ReceivedButtonContent],
		headerType: ReceivedButtonsHeaderType?,
		header: ReceivedButtonsHeaderContent?
	) {
		self.contentText = contentText
		self.footerText = footerText
		self.buttons = buttons
		self.headerType = headerType
		self.header = header
	}
}
