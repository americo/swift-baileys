public enum ReceivedButtonsResponseType: Equatable, Sendable {
	case unknown
	case displayText
	case unrecognized(Int)
}

public struct ReceivedButtonsResponseContent: Equatable, Sendable {
	public let selectedButtonID: String?
	public let selectedDisplayText: String?
	public let type: ReceivedButtonsResponseType?

	public init(selectedButtonID: String?, selectedDisplayText: String?, type: ReceivedButtonsResponseType?) {
		self.selectedButtonID = selectedButtonID
		self.selectedDisplayText = selectedDisplayText
		self.type = type
	}
}

public enum ReceivedListResponseType: Equatable, Sendable {
	case unknown
	case singleSelect
	case unrecognized(Int)
}

public struct ReceivedListResponseContent: Equatable, Sendable {
	public let title: String?
	public let listType: ReceivedListResponseType?
	public let selectedRowID: String?
	public let description: String?

	public init(title: String?, listType: ReceivedListResponseType?, selectedRowID: String?, description: String?) {
		self.title = title
		self.listType = listType
		self.selectedRowID = selectedRowID
		self.description = description
	}
}

public struct ReceivedTemplateButtonReplyContent: Equatable, Sendable {
	public let selectedID: String?
	public let selectedDisplayText: String?
	public let selectedIndex: UInt32?
	public let selectedCarouselCardIndex: UInt32?

	public init(
		selectedID: String?,
		selectedDisplayText: String?,
		selectedIndex: UInt32?,
		selectedCarouselCardIndex: UInt32?
	) {
		self.selectedID = selectedID
		self.selectedDisplayText = selectedDisplayText
		self.selectedIndex = selectedIndex
		self.selectedCarouselCardIndex = selectedCarouselCardIndex
	}
}

public enum ReceivedInteractiveResponseBodyFormat: Equatable, Sendable {
	case `default`
	case extensions1
	case unrecognized(Int)
}

public struct ReceivedInteractiveResponseBodyContent: Equatable, Sendable {
	public let text: String?
	public let format: ReceivedInteractiveResponseBodyFormat?

	public init(text: String?, format: ReceivedInteractiveResponseBodyFormat?) {
		self.text = text
		self.format = format
	}
}

public struct ReceivedNativeFlowResponseContent: Equatable, Sendable {
	public let name: String?
	public let paramsJSON: String?
	public let version: Int32?

	public init(name: String?, paramsJSON: String?, version: Int32?) {
		self.name = name
		self.paramsJSON = paramsJSON
		self.version = version
	}
}

public struct ReceivedInteractiveResponseContent: Equatable, Sendable {
	public let body: ReceivedInteractiveResponseBodyContent?
	public let nativeFlowResponse: ReceivedNativeFlowResponseContent?

	public init(
		body: ReceivedInteractiveResponseBodyContent?,
		nativeFlowResponse: ReceivedNativeFlowResponseContent?
	) {
		self.body = body
		self.nativeFlowResponse = nativeFlowResponse
	}
}
