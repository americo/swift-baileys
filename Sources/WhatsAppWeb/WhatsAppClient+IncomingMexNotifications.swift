import Foundation

extension WhatsAppClient {
	func handleMexNotification(_ node: BinaryNode) {
		guard let update = node.firstChild(named: "update"),
			  let opName = update.attrs["op_name"],
			  let response = mexResponse(from: update),
			  response["errors"] == nil,
			  let data = response["data"] as? [String: Any] else {
			return
		}

		switch opName {
		case "NotificationUserReachoutTimelockUpdate":
			if let payload = data["xwa2_notify_account_reachout_timelock"] as? [String: Any] {
				eventContinuation.yield(.reachoutTimelockUpdated(reachoutTimelockUpdate(from: payload)))
			}
		case "MessageCappingInfoNotification":
			if let payload = data["xwa2_notify_new_chat_messages_capping_info_update"] as? [String: Any] {
				eventContinuation.yield(.messageCappingUpdated(messageCappingUpdate(from: payload)))
			}
		default:
			break
		}
	}

	private func mexResponse(from node: BinaryNode) -> [String: Any]? {
		guard let data = node.contentData,
			  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return nil
		}

		return json
	}

	private func reachoutTimelockUpdate(from payload: [String: Any]) -> ReachoutTimelockUpdate {
		let isActive = payload["is_active"] as? Bool ?? false
		if !isActive {
			return ReachoutTimelockUpdate(isActive: false, enforcementType: "DEFAULT")
		}

		let timestamp = (payload["time_enforcement_ends"] as? String).flatMap(TimeInterval.init)
		return ReachoutTimelockUpdate(
			isActive: true,
			timeEnforcementEnds: timestamp.map { Date(timeIntervalSince1970: $0) },
			enforcementType: payload["enforcement_type"] as? String ?? "DEFAULT"
		)
	}

	private func messageCappingUpdate(from payload: [String: Any]) -> MessageCappingUpdate {
		MessageCappingUpdate(
			totalQuota: payload["total_quota"] as? Int,
			usedQuota: payload["used_quota"] as? Int,
			cycleStartTimestamp: payload["cycle_start_timestamp"] as? String,
			cycleEndTimestamp: payload["cycle_end_timestamp"] as? String,
			serverSentTimestamp: payload["server_sent_timestamp"] as? String,
			oteStatus: payload["ote_status"] as? String,
			mvStatus: payload["mv_status"] as? String,
			cappingStatus: payload["capping_status"] as? String
		)
	}
}

private extension BinaryNode {
	var contentData: Data? {
		guard let content else {
			return nil
		}

		switch content {
		case .data(let data):
			return data
		case .string(let string):
			return Data(string.utf8)
		case .nodes:
			return nil
		}
	}
}
