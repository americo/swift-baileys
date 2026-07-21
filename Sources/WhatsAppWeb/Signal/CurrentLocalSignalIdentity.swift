import Foundation

final class CurrentLocalSignalIdentity: @unchecked Sendable {
	private let lock = NSLock()
	private var currentJID: String?

	init(jid: String? = nil) {
		self.currentJID = jid
	}

	var jid: String? {
		lock.withLock {
			currentJID
		}
	}

	func update(_ jid: String?) {
		lock.withLock {
			currentJID = jid
		}
	}
}
