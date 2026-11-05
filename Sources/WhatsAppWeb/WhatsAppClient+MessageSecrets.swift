import Foundation

extension WhatsAppClient {
	/// Lets the client decrypt edits, which are encrypted with the secret of the message they change.
	public func configureMessageSecretResolver(_ resolver: (any MessageSecretResolving)?) {
		messageSecretResolver = resolver
	}
}
