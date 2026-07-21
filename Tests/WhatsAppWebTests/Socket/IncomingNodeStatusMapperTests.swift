import Testing
@testable import WhatsAppWeb

@Suite("Incoming node status mapper")
struct IncomingNodeStatusMapperTests {
	@Test("maps receipt types to message statuses like Baileys")
	func mapsReceiptTypesToMessageStatusesLikeBaileys() {
		#expect(IncomingReceiptStatusMapper.status(fromReceiptType: nil) == .deliveryAck)
		#expect(IncomingReceiptStatusMapper.status(fromReceiptType: "sender") == .serverAck)
		#expect(IncomingReceiptStatusMapper.status(fromReceiptType: "played") == .played)
		#expect(IncomingReceiptStatusMapper.status(fromReceiptType: "read") == .read)
		#expect(IncomingReceiptStatusMapper.status(fromReceiptType: "read-self") == .read)
		#expect(IncomingReceiptStatusMapper.status(fromReceiptType: "retry") == nil)
	}

	@Test("maps call nodes to call update statuses like Baileys")
	func mapsCallNodesToCallUpdateStatusesLikeBaileys() {
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "offer")) == .offer)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "offer_notice")) == .offer)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "terminate")) == .terminate)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "terminate", attrs: ["reason": "timeout"])) == .timeout)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "preaccept")) == .preaccept)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "transport")) == .transport)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "relaylatency")) == .relaylatency)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "reject")) == .reject)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "accept")) == .accept)
		#expect(IncomingCallStatusMapper.status(from: BinaryNode(tag: "mystery")) == .ringing)
	}
}
