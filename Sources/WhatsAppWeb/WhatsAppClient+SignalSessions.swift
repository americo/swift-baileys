import Foundation

extension WhatsAppClient {
	@discardableResult
	public func assertSessions(for jids: [String], force: Bool = false) async throws -> Bool {
		guard let signalSessionPreparer else {
			throw WhatsAppClientError.missingSignalSessionPreparer
		}

		return try await signalSessionPreparer.assertSessions(for: jids, force: force)
	}
}
