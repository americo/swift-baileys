public enum IncomingReceiptStatusMapper {
	public static func status(fromReceiptType type: String?) -> ReceivedMessageStatus? {
		switch type {
		case nil:
			.deliveryAck
		case "sender":
			.serverAck
		case "played":
			.played
		case "read", "read-self":
			.read
		default:
			nil
		}
	}
}

public enum IncomingCallStatusMapper {
	public static func status(from node: BinaryNode) -> WhatsAppCallUpdateType {
		switch node.tag {
		case "offer", "offer_notice":
			.offer
		case "terminate":
			node.attrs["reason"] == "timeout" ? .timeout : .terminate
		case "preaccept":
			.preaccept
		case "transport":
			.transport
		case "relaylatency":
			.relaylatency
		case "reject":
			.reject
		case "accept":
			.accept
		default:
			.ringing
		}
	}
}
