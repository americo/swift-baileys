import CryptoKit
import Foundation

enum ClientPayloadBuilder {
	/// Matches `WA` + protocol version 6 + dictionary version 3 used by WhatsApp Web.
	static let noiseHeader = Data([0x57, 0x41, 0x06, 0x03])

	/// Optional edge-routing prefix (`ED\0\1` + 3-byte length + routing info) sent before the WA header.
	static func introHeader(routingInfo: Data?) -> Data {
		var header = Data()
		if let routingInfo, !routingInfo.isEmpty {
			header.append(contentsOf: [0x45, 0x44, 0x00, 0x01])
			header.append(BigEndianEncoder.encode(routingInfo.count, count: 3))
			header.append(routingInfo)
		}
		header.append(noiseHeader)
		return header
	}

	static func make(
		credentials: AuthenticationCredentials,
		configuration: WhatsAppClientConfiguration,
		version: WhatsAppVersion
	) throws -> Proto_ClientPayload {
		var payload = Proto_ClientPayload()
		payload.connectType = .wifiUnknown
		payload.connectReason = .userActivated

		var userAgent = Proto_ClientPayload.UserAgent()
		userAgent.platform = .web
		userAgent.releaseChannel = .release
		userAgent.osVersion = "0.1"
		userAgent.device = "Desktop"
		userAgent.osBuildNumber = "0.1"
		userAgent.localeLanguageIso6391 = "en"
		userAgent.localeCountryIso31661Alpha2 = "US"
		userAgent.mnc = "000"
		userAgent.mcc = "000"
		var appVersion = Proto_ClientPayload.UserAgent.AppVersion()
		appVersion.primary = UInt32(version.primary)
		appVersion.secondary = UInt32(version.secondary)
		appVersion.tertiary = UInt32(version.tertiary)
		userAgent.appVersion = appVersion
		payload.userAgent = userAgent

		var webInfo = Proto_ClientPayload.WebInfo()
		// The server silently drops registrations that claim `.darwin`; `.webBrowser` is accepted.
		webInfo.webSubPlatform = .webBrowser
		payload.webInfo = webInfo

		if let me = credentials.me, let jid = JID(me.id), let user = UInt64(jid.user) {
			payload.passive = true
			payload.pull = true
			payload.username = user
			payload.device = UInt32(jid.device ?? 0)
			payload.lidDbMigrated = false
		} else {
			payload.passive = false
			payload.pull = false
			payload.devicePairingData = try registrationData(
				credentials: credentials,
				configuration: configuration,
				version: version
			)
		}
		return payload
	}

	private static func registrationData(
		credentials: AuthenticationCredentials,
		configuration: WhatsAppClientConfiguration,
		version: WhatsAppVersion
	) throws -> Proto_ClientPayload.DevicePairingRegistrationData {
		var data = Proto_ClientPayload.DevicePairingRegistrationData()
		data.buildHash = Data(Insecure.MD5.hash(data: Data(version.array.map(String.init).joined(separator: ".").utf8)))
		data.deviceProps = try deviceProps(configuration: configuration).serializedData()
		data.eRegid = BigEndianEncoder.encode(credentials.registrationID, count: 4)
		data.eKeytype = Data([0x05])
		data.eIdent = credentials.signedIdentityKey.publicKey
		data.eSkeyID = BigEndianEncoder.encode(credentials.signedPreKey.keyID, count: 3)
		data.eSkeyVal = credentials.signedPreKey.keyPair.publicKey
		data.eSkeySig = credentials.signedPreKey.signature
		return data
	}

	static func deviceProps(configuration: WhatsAppClientConfiguration) -> Proto_DeviceProps {
		var props = Proto_DeviceProps()
		props.os = "Mac OS"
		props.platformType = Int(configuration.companionPlatformID).flatMap(Proto_DeviceProps.PlatformType.init(rawValue:)) ?? .desktop
		props.requireFullSync = true
		var appVersion = Proto_DeviceProps.AppVersion()
		appVersion.primary = 10
		appVersion.secondary = 15
		appVersion.tertiary = 7
		props.version = appVersion
		var history = Proto_DeviceProps.HistorySyncConfig()
		history.storageQuotaMb = 10240
		history.inlineInitialPayloadInE2EeMsg = true
		history.supportCallLogHistory = false
		history.supportBotUserAgentChatHistory = true
		history.supportCagReactionsAndPolls = true
		history.supportBizHostedMsg = true
		history.supportRecentSyncChunkMessageCountTuning = true
		history.supportHostedGroupMsg = true
		history.supportFbidBotChatHistory = true
		history.supportMessageAssociation = true
		history.supportGroupHistory = false
		props.historySyncConfig = history
		return props
	}
}
