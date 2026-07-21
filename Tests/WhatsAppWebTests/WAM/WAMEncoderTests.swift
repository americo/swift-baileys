import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WAM encoder")
struct WAMEncoderTests {
	@Test("encodes WAM header and compact boolean event fields like Baileys")
	func encodesWAMHeaderAndCompactBooleanEventFields() throws {
		let data = try WAMEncoder.encode(
			WAMBinaryInfo(
				sequence: 7,
				events: [
					WAMEventInput(
						name: "WamClientErrors",
						props: [("isFromWamsys", .bool(true))]
					)
				]
			),
			events: [
				WAMEventDefinition(
					name: "WamClientErrors",
					id: 1144,
					weight: 1,
					props: ["isFromWamsys": 27]
				)
			]
		)

		#expect(data == Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x00, 0x07, 0x00,
			0x39, 0x78, 0x04, 0xff,
			0x26, 0x1b
		]))
	}

	@Test("encodes globals, strings, integers, and doubles with TypeScript-compatible headers")
	func encodesGlobalsStringsIntegersAndDoubles() throws {
		let data = try WAMEncoder.encode(
			WAMBinaryInfo(
				sequence: 258,
				events: [
					WAMEventInput(
						name: "FixtureEvent",
						props: [
							("shortText", .string("ok")),
							("wideInt", .integer(300)),
							("floatValue", .double(1.5))
						],
						globals: [
							("nullableGlobal", .null)
						]
					)
				]
			),
			events: [
				WAMEventDefinition(
					name: "FixtureEvent",
					id: 260,
					weight: 2,
					props: [
						"shortText": 1,
						"wideInt": 300,
						"floatValue": 2
					]
				)
			],
			globals: [
				WAMGlobalDefinition(name: "nullableGlobal", id: 9)
			]
		)

		#expect(data == Data([
			0x57, 0x41, 0x4d, 0x05, 0x01, 0x01, 0x02, 0x00,
			0x00, 0x09,
			0x39, 0x04, 0x01, 0xfe,
			0x81, 0x01, 0x02, 0x6f, 0x6b,
			0x49, 0x2c, 0x01, 0x2c, 0x01,
			0x76, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x3f
		]))
	}

	@Test("rejects unknown definitions and null event fields")
	func rejectsUnknownDefinitionsAndNullEventFields() throws {
		#expect(throws: WAMEncodingError.unknownEvent("Missing")) {
			try WAMEncoder.encode(WAMBinaryInfo(events: [WAMEventInput(name: "Missing")]), events: [])
		}

		#expect(throws: WAMEncodingError.unsupportedNullValue) {
			try WAMEncoder.encode(
				WAMBinaryInfo(events: [WAMEventInput(name: "FixtureEvent", props: [("field", .null)])]),
				events: [
					WAMEventDefinition(name: "FixtureEvent", id: 1, weight: 1, props: ["field": 1])
				]
			)
		}
	}
}
