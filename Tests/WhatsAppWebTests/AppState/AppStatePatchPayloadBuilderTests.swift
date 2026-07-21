import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("App-state patch payload builder")
struct AppStatePatchPayloadBuilderTests {
	@Test("builds sync action data for patch encoding")
	func buildsSyncActionDataForPatchEncoding() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .pin(
			jid: "123@s.whatsapp.net",
			pinned: true
		))

		let data = try AppStatePatchPayloadBuilder.syncActionData(for: patch)

		#expect(String(data: data.index, encoding: .utf8) == #"["pin_v1","123@s.whatsapp.net"]"#)
		#expect(data.value.hasPinAction)
		#expect(data.value.pinAction.pinned)
		#expect(data.padding.isEmpty)
		#expect(data.version == 5)
		#expect(try data.serializedData() == Data([
			0x0a, 0x1f,
			0x5b, 0x22, 0x70, 0x69, 0x6e, 0x5f, 0x76, 0x31, 0x22, 0x2c, 0x22, 0x31, 0x32, 0x33, 0x40, 0x73,
			0x2e, 0x77, 0x68, 0x61, 0x74, 0x73, 0x61, 0x70, 0x70, 0x2e, 0x6e, 0x65, 0x74, 0x22, 0x5d,
			0x12, 0x04, 0x2a, 0x02, 0x08, 0x01,
			0x1a, 0x00,
			0x20, 0x05
		]))
	}

	@Test("preserves remove operations at the patch boundary")
	func preservesRemoveOperationsAtPatchBoundary() throws {
		let patch = ChatModificationPatchBuilder.patch(for: .contact(
			jid: "123@s.whatsapp.net",
			contact: nil
		))
		let data = try AppStatePatchPayloadBuilder.syncActionData(for: patch)

		#expect(patch.operation == .remove)
		#expect(String(data: data.index, encoding: .utf8) == #"["contact","123@s.whatsapp.net"]"#)
		#expect(data.value.hasContactAction)
		#expect(try data.value.serializedData() == Data([0x1a, 0x00]))
	}
}
