import Foundation

public extension AuthenticationCredentials {
	func assertMeID() throws -> String {
		guard let id = me?.id, !id.isEmpty else {
			throw AuthenticationCredentialsValidationError.missingAuthenticatedUser
		}

		return id
	}
}

public enum AuthenticationCredentialsValidationError: Error, Equatable, Sendable {
	case missingAuthenticatedUser
}
