import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client product messages")
struct WhatsAppClientProductMessageTests {
	@Test("sends product messages after uploading the product image")
	func sendsProductMessagesAfterUploadingTheProductImage() async throws {
		let transport = MockMessageSendWebSocketTransport()
		let callOrder = MessageSendCallOrder()
		let sessionPreparer = StubSignalSessionPreparer(callOrder: callOrder)
		let encryptor = StubMessageSendEncryptor(results: [
			EncryptedMessage(type: "msg", ciphertext: Data([0xef]))
		], callOrder: callOrder)
		let deviceResolver = StubMessageDeviceResolver(result: ["123.0@s.whatsapp.net"])
		let mediaUploader = StubWhatsAppMediaUploader(result: MediaUploadResult(
			mediaURL: "https://media.example/product",
			directPath: "/v/t62.7118-24/product",
			timestamp: 1_700_000_001,
			fileID: 123
		))
		let mediaKey = try hexData("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
		let client = WhatsAppClient(
			transportFactory: { _ in transport },
			messageEncryptor: encryptor,
			messageDeviceResolver: deviceResolver,
			signalSessionPreparer: sessionPreparer,
			messageEncoder: MessageEncoder(randomByte: { 0x00 }),
			mediaUploader: mediaUploader,
			mediaKeyGenerator: StubMediaKeyGenerator(mediaKey: mediaKey),
			mediaKeyTimestamp: { 1_700_000_000 }
		)
		try await client.connect()

		let messageID = try await client.sendProductMessage(
			to: "123@s.whatsapp.net",
			imageData: Data("swift baileys media fixture".utf8),
			product: OutgoingProductContent(
				productID: "product-123",
				title: "Running shoes",
				description: "Lightweight shoes",
				currencyCode: "MZN",
				priceAmount1000: 15_990_000,
				retailerID: "sku-123",
				url: "https://shop.example/products/product-123",
				businessOwnerJID: "258840000100@s.whatsapp.net",
				body: "Available now",
				footer: "Tap to view"
			),
			messageID: "3EB0PRODUCT"
		)

		let expectedEncryptedFile = try hexData("3a3018e9b6b731f67593006398f95c50dc0d3938ce1c2652b64845c2c9eeb87b5ecae5e287aaeebc57b1")
		let expectedFileEncSHA256 = try hexData("00f13c349529b3f7026966a4a5861f8241f7e03e42e4e649f8d3bb998f3c5d03")
		let expectedFileSHA256 = try hexData("fe07adf759085af9956dd79b5a28e04016ddbbbbced71143a470315cc18a05ce")

		#expect(messageID == "3EB0PRODUCT")
		#expect(await mediaUploader.calls == [
			MediaUploadCall(
				data: expectedEncryptedFile,
				fileEncSha256Base64: expectedFileEncSHA256.base64EncodedString(),
				mediaType: .image
			)
		])
		#expect(await deviceResolver.calls == ["123@s.whatsapp.net"])
		#expect(await sessionPreparer.calls == [
			SignalSessionPreparationCall(jids: ["123.0@s.whatsapp.net"], force: false)
		])

		let encryptorCalls = await encryptor.calls
		let protobufMessage = try Proto_Message(serializedBytes: encryptorCalls[0].data.dropLast())
		#expect(protobufMessage.productMessage.product.productImage.url == "https://media.example/product")
		#expect(protobufMessage.productMessage.product.productImage.directPath == "/v/t62.7118-24/product")
		#expect(protobufMessage.productMessage.product.productImage.mediaKey == mediaKey)
		#expect(protobufMessage.productMessage.product.productImage.fileEncSha256 == expectedFileEncSHA256)
		#expect(protobufMessage.productMessage.product.productImage.fileSha256 == expectedFileSHA256)
		#expect(protobufMessage.productMessage.product.productImage.fileLength == UInt64(Data("swift baileys media fixture".utf8).count))
		#expect(protobufMessage.productMessage.product.title == "Running shoes")
		#expect(protobufMessage.productMessage.product.priceAmount1000 == 15_990_000)
		#expect(protobufMessage.productMessage.businessOwnerJid == "258840000100@s.whatsapp.net")

		var codec = NoiseFrameCodec()
		let frames = codec.decode(await transport.sentFrames[0])
		let stanza = try BinaryNodeDecoder().decode(frames[0])
		#expect(stanza.attrs["id"] == "3EB0PRODUCT")
		#expect(stanza.attrs["to"] == "123@s.whatsapp.net")
	}
}
