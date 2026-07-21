import Foundation

public struct NoiseKeyPair: Equatable, Sendable {
	public let privateKey: Data
	public let publicKey: Data

	public init(privateKey: Data, publicKey: Data) {
		self.privateKey = privateKey
		self.publicKey = publicKey
	}
}
