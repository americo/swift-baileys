import Foundation

extension WhatsAppClient {
	public func configureEventResponseContextResolver(_ resolver: (any EventResponseContextResolving)?) {
		eventResponseContextResolver = resolver
	}
}
