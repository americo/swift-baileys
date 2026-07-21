import Foundation

extension WhatsAppClient {
	public func configurePollVoteContextResolver(_ resolver: (any PollVoteContextResolving)?) {
		pollVoteContextResolver = resolver
	}
}
