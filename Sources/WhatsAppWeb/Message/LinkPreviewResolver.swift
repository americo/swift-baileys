import Foundation

public protocol LinkPreviewResolving: Sendable {
	func linkPreview(for url: String) async throws -> OutgoingLinkPreviewContent?
}
