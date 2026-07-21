import Foundation

public enum SignalDecryptionJIDResolver {
	public typealias LIDMappingResolver = @Sendable (_ phoneNumberJID: String) async throws -> String?

	public static func resolve(
		senderJID: String,
		resolveLIDForPN: LIDMappingResolver? = nil
	) async throws -> String {
		if senderJID.isLIDUserJID || senderJID.isHostedLIDUserJID {
			return senderJID
		}

		return try await resolveLIDForPN?(senderJID) ?? senderJID
	}
}
