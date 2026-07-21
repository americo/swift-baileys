import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WAM definitions")
struct WAMDefinitionsTests {
	@Test("loads Baileys web WAM event and global definitions")
	func loadsBaileysWebDefinitions() throws {
		let definitions = try WAMDefinitions.web()
		let event = try #require(definitions.event(named: "WamClientErrors"))
		let global = try #require(definitions.global(named: "platform"))

		#expect(definitions.events.count == 313)
		#expect(definitions.globals.count == 48)
		#expect(event.id == 1144)
		#expect(event.weight == 1)
		#expect(event.props["isFromWamsys"] == 27)
		#expect(global.id == 11)
	}

	@Test("encodes known WAM events with bundled web definitions")
	func encodesKnownEventsWithBundledDefinitions() throws {
		let info = WAMBinaryInfo(
			sequence: 7,
			events: [
				WAMEventInput(
					name: "WamClientErrors",
					props: [("isFromWamsys", .bool(true))]
				)
			]
		)
		let data = try WAMEncoder.encode(
			info,
			definitions: WAMDefinitions.web()
		)
		let defaultData = try WAMEncoder.encode(info)

		#expect(data == defaultData)
		#expect(data == Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x00, 0x07, 0x00,
			0x39, 0x78, 0x04, 0xff,
			0x26, 0x1b
		]))
	}

	@Test("encodes bundled globals without explicit definition tables")
	func encodesBundledGlobalsWithoutExplicitTables() throws {
		let data = try WAMEncoder.encode(
			WAMBinaryInfo(
				sequence: 7,
				events: [
					WAMEventInput(
						name: "WamClientErrors",
						props: [("isFromWamsys", .bool(false))],
						globals: [("platform", .integer(17))]
					)
				]
			)
		)

		#expect(data == Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x00, 0x07, 0x00,
			0x30, 0x0b, 0x11,
			0x39, 0x78, 0x04, 0xff,
			0x16, 0x1b
		]))
	}
}
