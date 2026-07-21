import Foundation

public struct BaileysMessageDevice: Equatable, Sendable {
	public let user: String
	public let device: Int
	public let jid: String

	public init(user: String, device: Int, jid: String) {
		self.user = user
		self.device = device
		self.jid = jid
	}
}

extension WhatsAppClient {
	public func getUSyncDevices(
		_ jids: [String],
		useCache: Bool = true,
		ignoreZeroDevices: Bool = false
	) async throws -> [BaileysMessageDevice] {
		guard let messageDeviceResolver else {
			throw WhatsAppClientError.missingMessageDeviceResolver
		}

		var devices: [BaileysMessageDevice] = []
		for rawJID in jids {
			guard let jid = JID(rawJID) else {
				throw MessageDeviceResolverError.invalidJID
			}

			if let device = jid.device {
				if !ignoreZeroDevices || device != 0 {
					devices.append(BaileysMessageDevice(user: jid.user, device: device, jid: jid.rawValue))
				}
				continue
			}

			let resolved = try await messageDeviceResolver.deviceJIDs(for: jid.normalizedUser, useCache: useCache)
			for resolvedJID in resolved {
				guard let deviceJID = parseResolvedDeviceJID(resolvedJID), let device = deviceJID.device else {
					continue
				}

				if ignoreZeroDevices && device == 0 {
					continue
				}

				devices.append(BaileysMessageDevice(user: deviceJID.user, device: device, jid: resolvedJID))
			}
		}

		return devices
	}

	private func parseResolvedDeviceJID(_ rawValue: String) -> JID? {
		if let jid = JID(rawValue), jid.device != nil {
			return jid
		}

		guard let separator = rawValue.firstIndex(of: "@") else {
			return nil
		}

		let userAndDevice = rawValue[..<separator]
		guard let deviceSeparator = userAndDevice.lastIndex(of: ".") else {
			return nil
		}

		let canonical = rawValue.replacingCharacters(in: deviceSeparator...deviceSeparator, with: ":")
		return JID(canonical)
	}
}
