import Foundation

public struct AuthenticationKeyPair: Codable, Equatable, Sendable {
	public var privateKey: Data
	public var publicKey: Data

	public init(privateKey: Data, publicKey: Data) {
		self.privateKey = privateKey
		self.publicKey = publicKey
	}
}

public struct SignedAuthenticationKeyPair: Codable, Equatable, Sendable {
	public var keyPair: AuthenticationKeyPair
	public var signature: Data
	public var keyID: Int
	public var timestampSeconds: Int?

	public init(
		keyPair: AuthenticationKeyPair,
		signature: Data,
		keyID: Int,
		timestampSeconds: Int? = nil
	) {
		self.keyPair = keyPair
		self.signature = signature
		self.keyID = keyID
		self.timestampSeconds = timestampSeconds
	}
}

public struct WhatsAppUser: Codable, Equatable, Sendable {
	public var id: String
	public var name: String?
	public var lid: String?

	public init(id: String, name: String? = nil, lid: String? = nil) {
		self.id = id
		self.name = name
		self.lid = lid
	}
}

public struct SignalProtocolAddress: Codable, Equatable, Hashable, Sendable {
	public var name: String
	public var deviceID: Int

	public var storageKey: String {
		"\(name).\(deviceID)"
	}

	public init(name: String, deviceID: Int) {
		self.name = name
		self.deviceID = deviceID
	}

	public static func validated(jid rawJID: String) throws -> SignalProtocolAddress {
		guard let address = SignalProtocolAddress(jid: rawJID) else {
			throw SignalProtocolAddressValidationError.invalidJID
		}

		return address
	}

	public init?(jid rawJID: String) {
		guard let jid = JID(rawJID) else {
			return nil
		}

		let userAndDevice = rawJID.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)[0]
		if userAndDevice.contains(":"), jid.device == nil {
			return nil
		}

		self.name = jid.domainType == .whatsapp ? jid.user : "\(jid.user)_\(jid.domainType.rawValue)"
		self.deviceID = jid.device ?? 0
	}
}

public enum SignalProtocolAddressValidationError: Error, Equatable, Sendable {
	case invalidJID
}

public struct SignalIdentity: Codable, Equatable, Sendable {
	public var identifier: SignalProtocolAddress
	public var identifierKey: Data

	public init(identifier: SignalProtocolAddress, identifierKey: Data) {
		self.identifier = identifier
		self.identifierKey = identifierKey
	}
}

public struct SignedDeviceIdentityAccount: Codable, Equatable, Sendable {
	public var details: Data
	public var accountSignatureKey: Data
	public var accountSignature: Data
	public var deviceSignature: Data?

	public init(
		details: Data,
		accountSignatureKey: Data,
		accountSignature: Data,
		deviceSignature: Data? = nil
	) {
		self.details = details
		self.accountSignatureKey = accountSignatureKey
		self.accountSignature = accountSignature
		self.deviceSignature = deviceSignature
	}
}

public struct AccountSettings: Codable, Equatable, Sendable {
	public var unarchiveChats: Bool
	public var defaultDisappearingMode: AccountDisappearingModeSetting?

	public init(
		unarchiveChats: Bool = false,
		defaultDisappearingMode: AccountDisappearingModeSetting? = nil
	) {
		self.unarchiveChats = unarchiveChats
		self.defaultDisappearingMode = defaultDisappearingMode
	}
}

public struct AccountDisappearingModeSetting: Codable, Equatable, Sendable {
	public var ephemeralExpiration: Int
	public var ephemeralSettingTimestamp: Int

	public init(ephemeralExpiration: Int, ephemeralSettingTimestamp: Int) {
		self.ephemeralExpiration = ephemeralExpiration
		self.ephemeralSettingTimestamp = ephemeralSettingTimestamp
	}
}

public struct ProcessedHistoryMessage: Codable, Equatable, Sendable {
	public var key: WhatsAppMessageKey
	public var messageTimestamp: UInt64?

	public init(key: WhatsAppMessageKey, messageTimestamp: UInt64?) {
		self.key = key
		self.messageTimestamp = messageTimestamp
	}
}

public struct AuthenticationCredentials: Codable, Equatable, Sendable {
	public var noiseKey: AuthenticationKeyPair
	public var pairingEphemeralKeyPair: AuthenticationKeyPair
	public var signedIdentityKey: AuthenticationKeyPair
	public var signedPreKey: SignedAuthenticationKeyPair
	public var registrationID: Int
	public var advSecretKey: String
	public var me: WhatsAppUser?
	public var account: SignedDeviceIdentityAccount?
	public var signalIdentities: [SignalIdentity]
	public var platform: String?
	public var nextPreKeyID: Int
	public var firstUnuploadedPreKeyID: Int
	public var accountSyncCounter: Int
	public var accountSettings: AccountSettings
	public var registered: Bool
	public var pairingCode: String?
	public var lastPropertyHash: String?
	public var lastAccountSyncTimestamp: Int?
	public var routingInfo: Data?
	public var myAppStateKeyID: String?
	public var processedHistoryMessages: [ProcessedHistoryMessage]

	private enum CodingKeys: String, CodingKey {
		case noiseKey
		case pairingEphemeralKeyPair
		case signedIdentityKey
		case signedPreKey
		case registrationID
		case advSecretKey
		case me
		case account
		case signalIdentities
		case platform
		case nextPreKeyID
		case firstUnuploadedPreKeyID
		case accountSyncCounter
		case accountSettings
		case registered
		case pairingCode
		case lastPropertyHash
		case lastAccountSyncTimestamp
		case routingInfo
		case myAppStateKeyID = "myAppStateKeyId"
		case processedHistoryMessages
	}

	private enum LegacyCodingKeys: String, CodingKey {
		case myAppStateKeyID
	}

	public init(
		noiseKey: AuthenticationKeyPair,
		pairingEphemeralKeyPair: AuthenticationKeyPair,
		signedIdentityKey: AuthenticationKeyPair,
		signedPreKey: SignedAuthenticationKeyPair,
		registrationID: Int,
		advSecretKey: String,
		me: WhatsAppUser? = nil,
		account: SignedDeviceIdentityAccount? = nil,
		signalIdentities: [SignalIdentity] = [],
		platform: String? = nil,
		nextPreKeyID: Int,
		firstUnuploadedPreKeyID: Int,
		accountSyncCounter: Int,
		accountSettings: AccountSettings = AccountSettings(),
		registered: Bool,
		pairingCode: String? = nil,
		lastPropertyHash: String? = nil,
		lastAccountSyncTimestamp: Int? = nil,
		routingInfo: Data? = nil,
		myAppStateKeyID: String? = nil,
		processedHistoryMessages: [ProcessedHistoryMessage] = []
	) {
		self.noiseKey = noiseKey
		self.pairingEphemeralKeyPair = pairingEphemeralKeyPair
		self.signedIdentityKey = signedIdentityKey
		self.signedPreKey = signedPreKey
		self.registrationID = registrationID
		self.advSecretKey = advSecretKey
		self.me = me
		self.account = account
		self.signalIdentities = signalIdentities
		self.platform = platform
		self.nextPreKeyID = nextPreKeyID
		self.firstUnuploadedPreKeyID = firstUnuploadedPreKeyID
		self.accountSyncCounter = accountSyncCounter
		self.accountSettings = accountSettings
		self.registered = registered
		self.pairingCode = pairingCode
		self.lastPropertyHash = lastPropertyHash
		self.lastAccountSyncTimestamp = lastAccountSyncTimestamp
		self.routingInfo = routingInfo
		self.myAppStateKeyID = myAppStateKeyID
		self.processedHistoryMessages = processedHistoryMessages
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
		self.noiseKey = try container.decode(AuthenticationKeyPair.self, forKey: .noiseKey)
		self.pairingEphemeralKeyPair = try container.decode(AuthenticationKeyPair.self, forKey: .pairingEphemeralKeyPair)
		self.signedIdentityKey = try container.decode(AuthenticationKeyPair.self, forKey: .signedIdentityKey)
		self.signedPreKey = try container.decode(SignedAuthenticationKeyPair.self, forKey: .signedPreKey)
		self.registrationID = try container.decode(Int.self, forKey: .registrationID)
		self.advSecretKey = try container.decode(String.self, forKey: .advSecretKey)
		self.me = try container.decodeIfPresent(WhatsAppUser.self, forKey: .me)
		self.account = try container.decodeIfPresent(SignedDeviceIdentityAccount.self, forKey: .account)
		self.signalIdentities = try container.decode([SignalIdentity].self, forKey: .signalIdentities)
		self.platform = try container.decodeIfPresent(String.self, forKey: .platform)
		self.nextPreKeyID = try container.decode(Int.self, forKey: .nextPreKeyID)
		self.firstUnuploadedPreKeyID = try container.decode(Int.self, forKey: .firstUnuploadedPreKeyID)
		self.accountSyncCounter = try container.decode(Int.self, forKey: .accountSyncCounter)
		self.accountSettings = try container.decode(AccountSettings.self, forKey: .accountSettings)
		self.registered = try container.decode(Bool.self, forKey: .registered)
		self.pairingCode = try container.decodeIfPresent(String.self, forKey: .pairingCode)
		self.lastPropertyHash = try container.decodeIfPresent(String.self, forKey: .lastPropertyHash)
		self.lastAccountSyncTimestamp = try container.decodeIfPresent(Int.self, forKey: .lastAccountSyncTimestamp)
		self.routingInfo = try container.decodeIfPresent(Data.self, forKey: .routingInfo)
		self.myAppStateKeyID = try container.decodeIfPresent(String.self, forKey: .myAppStateKeyID)
			?? legacyContainer.decodeIfPresent(String.self, forKey: .myAppStateKeyID)
		self.processedHistoryMessages = try container.decodeIfPresent(
			[ProcessedHistoryMessage].self,
			forKey: .processedHistoryMessages
		) ?? []
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(noiseKey, forKey: .noiseKey)
		try container.encode(pairingEphemeralKeyPair, forKey: .pairingEphemeralKeyPair)
		try container.encode(signedIdentityKey, forKey: .signedIdentityKey)
		try container.encode(signedPreKey, forKey: .signedPreKey)
		try container.encode(registrationID, forKey: .registrationID)
		try container.encode(advSecretKey, forKey: .advSecretKey)
		try container.encodeIfPresent(me, forKey: .me)
		try container.encodeIfPresent(account, forKey: .account)
		try container.encode(signalIdentities, forKey: .signalIdentities)
		try container.encodeIfPresent(platform, forKey: .platform)
		try container.encode(nextPreKeyID, forKey: .nextPreKeyID)
		try container.encode(firstUnuploadedPreKeyID, forKey: .firstUnuploadedPreKeyID)
		try container.encode(accountSyncCounter, forKey: .accountSyncCounter)
		try container.encode(accountSettings, forKey: .accountSettings)
		try container.encode(registered, forKey: .registered)
		try container.encodeIfPresent(pairingCode, forKey: .pairingCode)
		try container.encodeIfPresent(lastPropertyHash, forKey: .lastPropertyHash)
		try container.encodeIfPresent(lastAccountSyncTimestamp, forKey: .lastAccountSyncTimestamp)
		try container.encodeIfPresent(routingInfo, forKey: .routingInfo)
		try container.encodeIfPresent(myAppStateKeyID, forKey: .myAppStateKeyID)
		try container.encode(processedHistoryMessages, forKey: .processedHistoryMessages)
	}
}
