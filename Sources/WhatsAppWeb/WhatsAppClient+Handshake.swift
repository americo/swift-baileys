import CryptoKit
import Foundation

enum WhatsAppHandshakeError: Error {
	case connectionClosed
	case unexpectedServerResponse
}

extension WhatsAppClient {
	/// Runs the Noise XX handshake over an open transport and returns the transport cipher state
	/// plus the inbound frame codec (it may already hold bytes that followed the server hello).
	func performNoiseHandshake(
		over transport: any WhatsAppWebSocketTransport,
		credentials: AuthenticationCredentials,
		version: WhatsAppVersion
	) async throws -> (NoiseTransportState, NoiseFrameCodec) {
		let ephemeral = Curve25519.KeyAgreement.PrivateKey()
		let ephemeralPair = NoiseKeyPair(
			privateKey: ephemeral.rawRepresentation,
			publicKey: ephemeral.publicKey.rawRepresentation
		)
		let staticPair = NoiseKeyPair(
			privateKey: credentials.noiseKey.privateKey,
			publicKey: credentials.noiseKey.publicKey
		)
		var processor = NoiseClientHandshakeProcessor(
			header: ClientPayloadBuilder.noiseHeader,
			ephemeralKeyPair: ephemeralPair,
			staticKeyPair: staticPair
		)

		outboundFrameCodec = NoiseFrameCodec(introHeader: ClientPayloadBuilder.introHeader(routingInfo: credentials.routingInfo))
		var hello = Proto_HandshakeMessage()
		hello.clientHello.ephemeral = ephemeralPair.publicKey
		try await transport.send(outboundFrameCodec.encode(hello.serializedData()))

		var inbound = NoiseFrameCodec()
		let serverHelloFrame = try await nextFrame(from: transport, codec: &inbound)
		let serverHello = try Proto_HandshakeMessage(serializedBytes: serverHelloFrame)
		let result = try processor.processServerHello(serverHello)

		let payload = try ClientPayloadBuilder.make(
			credentials: credentials,
			configuration: configuration,
			version: version
		)
		let encryptedPayload = try processor.encryptClientPayload(payload.serializedData())

		var finish = Proto_HandshakeMessage()
		finish.clientFinish.static = result.clientStaticCiphertext
		finish.clientFinish.payload = encryptedPayload
		try await transport.send(outboundFrameCodec.encode(finish.serializedData()))

		return (try processor.makeTransportState(), inbound)
	}

	private func nextFrame(from transport: any WhatsAppWebSocketTransport, codec: inout NoiseFrameCodec) async throws -> Data {
		while true {
			guard let data = try await transport.receive() else {
				throw WhatsAppHandshakeError.connectionClosed
			}
			if let frame = codec.decode(data).first {
				return frame
			}
		}
	}
}
