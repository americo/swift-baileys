import Foundation

public enum WhatsAppClientMessageCapability: CaseIterable, Equatable, Hashable, Sendable {
	case directSend
	case groupSend
	case mediaSend
	case incomingDecrypt
	case preKeyUpload
	case retryResend
}

public enum WhatsAppClientMessageDependency: Equatable, Hashable, Sendable {
	case messageEncryptor
	case groupMessageEncryptor
	case messageDeviceResolver
	case signalSessionPreparer
	case mediaUploader
	case incomingSignalDecryptor
	case preKeyUploaderOrAuthenticationState
}

public struct WhatsAppClientMessageDependencyError: Error, Equatable, Sendable {
	public let missingByCapability: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]]

	public init(
		missingByCapability: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]]
	) {
		self.missingByCapability = missingByCapability
	}
}

extension WhatsAppClient {
	public func availableMessageCapabilities() -> Set<WhatsAppClientMessageCapability> {
		Set(WhatsAppClientMessageCapability.allCases.filter {
			missingMessageDependencies(for: $0).isEmpty
		})
	}

	public func missingMessageDependencies() -> [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]] {
		var missingByCapability: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]] = [:]

		for capability in WhatsAppClientMessageCapability.allCases {
			let missing = missingMessageDependencies(for: capability)
			if !missing.isEmpty {
				missingByCapability[capability] = missing
			}
		}

		return missingByCapability
	}

	public func assertMessageCapabilities(
		_ capabilities: Set<WhatsAppClientMessageCapability> = Set(WhatsAppClientMessageCapability.allCases)
	) throws {
		var missingByCapability: [WhatsAppClientMessageCapability: [WhatsAppClientMessageDependency]] = [:]

		for capability in capabilities {
			let missing = missingMessageDependencies(for: capability)
			if !missing.isEmpty {
				missingByCapability[capability] = missing
			}
		}

		if !missingByCapability.isEmpty {
			throw WhatsAppClientMessageDependencyError(missingByCapability: missingByCapability)
		}
	}

	public func missingMessageDependencies(
		for capability: WhatsAppClientMessageCapability
	) -> [WhatsAppClientMessageDependency] {
		var missing: [WhatsAppClientMessageDependency] = []

		if capability == .directSend
			|| capability == .groupSend
			|| capability == .mediaSend
			|| capability == .retryResend {
			if messageEncryptor == nil {
				missing.append(.messageEncryptor)
			}
			if messageDeviceResolver == nil {
				missing.append(.messageDeviceResolver)
			}
			if signalSessionPreparer == nil {
				missing.append(.signalSessionPreparer)
			}
		}
		if capability == .groupSend, groupMessageEncryptor == nil {
			missing.insert(.groupMessageEncryptor, at: min(1, missing.count))
		}
		if capability == .mediaSend, mediaUploader == nil {
			missing.append(.mediaUploader)
		}
		if capability == .incomingDecrypt, messageDecryptor == nil {
			missing.append(.incomingSignalDecryptor)
		}
		if capability == .preKeyUpload, preKeyUploader == nil, authenticationState == nil {
			missing.append(.preKeyUploaderOrAuthenticationState)
		}

		return missing
	}
}
