import Foundation

extension WhatsAppClient {
	static func makeIncomingMessageDecryptor(
		signalDecryptor: any SignalMessageDecrypting,
		localSignalIdentity: CurrentLocalSignalIdentity,
		keys: (any SignalKeyStore)?
	) -> SignalIncomingMessageDecryptor {
		SignalIncomingMessageDecryptor(
			signalDecryptor: signalDecryptor,
			localJIDProvider: { [localSignalIdentity] in
				localSignalIdentity.jid
			},
			decryptionJIDResolver: { phoneNumberJID in
				guard let keys else {
					return nil
				}

				return try await LIDMappingStore.lid(for: phoneNumberJID, in: keys)
			}
		)
	}

	func storeLIDMappings(_ mappings: [LIDMapping]) async throws {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		try await LIDMappingStore.store(mappings, in: authenticationState.keys)
	}
}
