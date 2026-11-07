import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Call links")
struct CallLinkTests {
	private let videoLink = CallLink(token: "TOKEN", media: .video)
	private let creator = "100001:1@lid"

	private func ack(type: String, error: String? = nil, _ children: [BinaryNode]) -> BinaryNode {
		BinaryNode(
			tag: "ack",
			attrs: BinaryNodeAttributes.trimmingUndefined([
				("class", "call"),
				("type", type),
				("error", error)
			]),
			content: .nodes(children)
		)
	}

	private func room(enabled: Bool = true, media: String = "video", token: String = "TOKEN", users: [BinaryNode] = []) -> BinaryNode {
		BinaryNode(
			tag: "waiting_room",
			attrs: [
				"call-id": "CID",
				"call-creator": creator,
				"link-token": token,
				"media": media,
				"enabled": enabled ? "1" : "0",
				"is_admin": "0",
				"transaction-id": "4"
			],
			content: .nodes(users)
		)
	}

	private func roster(media: String = "video") -> BinaryNode {
		BinaryNode(tag: "group_info", attrs: [
			"call-id": "CID",
			"call-creator": creator,
			"transaction-id": "5",
			"media": media,
			"connected-limit": "8"
		])
	}

	@Test("a link reads from what people share, and from nothing else", arguments: [
		("https://call.whatsapp.com/video/AbC123", "AbC123", CallLinkMedia.video),
		("  https://call.whatsapp.com/voice/x", nil, nil),
		("https://call.whatsapp.com/audio/AbC123?x=1#y", "AbC123", .audio),
		("call.whatsapp.com/audio/AbC123", "AbC123", .audio),
		("http://call.whatsapp.com/audio/AbC123", nil, nil),
		("https://evil.example/audio/AbC123", nil, nil),
		("https://call.whatsapp.com.evil.example/audio/AbC123", nil, nil),
		("https://call.whatsapp.com/audio", nil, nil),
		("https://call.whatsapp.com/audio/a/b", nil, nil),
		("AbC123", nil, nil)
	] as [(String, String?, CallLinkMedia?)])
	func readsLinks(text: String, token: String?, media: CallLinkMedia?) {
		let link = CallLink(url: text)
		#expect(link?.token == token)
		#expect(link?.media == media)
	}

	@Test("a link's address goes back to the same link")
	func urlRoundTrip() {
		#expect(videoLink.url == "https://call.whatsapp.com/video/TOKEN")
		#expect(CallLink(url: videoLink.url) == videoLink)
	}

	@Test("requests about a link go to the call service, and survive the wire")
	func serviceRoute() throws {
		let create = CallStanzaBuilder.linkCreate(media: .video, stanzaID: "REQ")
		#expect(create.attrs["to"] == "@call")
		#expect(create.firstChild(named: "link_create")?.attrs["media"] == "video")

		let decoded = try BinaryNodeDecoder().decode(BinaryNodeEncoder().encode(create))
		#expect(decoded.attrs["to"] == "@call")

		let query = CallStanzaBuilder.linkQuery(link: videoLink, stanzaID: "REQ")
		#expect(query.firstChild(named: "link_query")?.attrs["token"] == "TOKEN")
	}

	@Test("joining states the media this client handles, in the order the service expects")
	func joinShape() throws {
		let video = try #require(CallStanzaBuilder.linkJoin(link: videoLink, stanzaID: "REQ").firstChild(named: "link_join"))
		guard case let .nodes(children)? = video.content else {
			Issue.record("no children")
			return
		}
		#expect(children.map(\.tag) == ["audio", "video", "net", "capability"])
		#expect(video.firstChild(named: "capability")?.content == .data(CallCapability.standardOpusVideoOffer))
		#expect(video.firstChild(named: "audio")?.attrs["rate"] == "16000")

		let audio = try #require(CallStanzaBuilder.linkJoin(
			link: CallLink(token: "TOKEN", media: .audio),
			stanzaID: "REQ"
		).firstChild(named: "link_join"))
		guard case let .nodes(audioChildren)? = audio.content else {
			Issue.record("no children")
			return
		}
		#expect(audioChildren.map(\.tag) == ["audio", "net", "capability"])
		#expect(audio.firstChild(named: "capability")?.content == .data(CallCapability.standardOpusOffer))
	}

	@Test("a waiting room's controls go to the call, naming who they are about")
	func waitingRoomShape() throws {
		let admit = CallStanzaBuilder.waitingRoomAdmit(callID: "CID", callCreator: creator, user: "200002@lid", stanzaID: "REQ")
		#expect(admit.attrs["to"] == "CID@call")
		#expect(admit.firstChild(named: "waiting_room_admit")?.firstChild(named: "user")?.attrs["jid"] == "200002@lid")

		let deny = CallStanzaBuilder.waitingRoomDeny(callID: "CID", callCreator: creator, user: "200002@lid", stanzaID: "REQ")
		#expect(deny.firstChild(named: "waiting_room_deny")?.attrs["call-id"] == "CID")

		let toggle = CallStanzaBuilder.waitingRoomToggle(callID: "CID", callCreator: creator, enabled: false, stanzaID: "REQ")
		#expect(toggle.firstChild(named: "waiting_room_toggle")?.attrs["enabled"] == "0")

		let heartbeat = CallStanzaBuilder.waitingRoomHeartbeat(callID: "CID", callCreator: creator, stanzaID: "REQ")
		#expect(heartbeat.attrs["to"] == "CID@call")
		#expect(heartbeat.firstChild(named: "heartbeat")?.attrs["type"] == "waiting_room")
	}

	@Test("a screen share states its version")
	func screenShareShape() throws {
		let node = CallStanzaBuilder.screenShare(
			callID: "CID",
			to: "CID@call",
			callCreator: creator,
			stanzaID: "REQ",
			state: .started
		)
		let action = try #require(node.firstChild(named: "screen_share"))
		#expect(action.attrs["screenshare_state"] == "1")
		#expect(action.attrs["version"] == "2")
		#expect(IncomingCallStatusMapper.status(from: action) == .screenShare)
	}

	@Test("a created link comes from the ack, and a refusal is one")
	func createAck() throws {
		let link = try CallLink.parse(createAck: ack(type: "link_create", [
			BinaryNode(tag: "link_create", attrs: ["token": "TOKEN", "media": "video"])
		]))
		#expect(link == videoLink)

		#expect(throws: GroupCallStanzaError.rejected("403")) {
			try CallLink.parse(createAck: ack(type: "link_create", error: "403", []))
		}
	}

	@Test("a preview need not have a waiting room")
	func previewAck() throws {
		let bare = try CallLinkPreview.parse(queryAck: ack(type: "link_query", [BinaryNode(
			tag: "link_query",
			attrs: ["token": "TOKEN", "media": "video", "link_creator": creator]
		)]))
		#expect(bare.link == videoLink)
		#expect(bare.creator == creator)
		#expect(!bare.isApprovalRequired)
		#expect(!bare.isAdmin)

		let full = try CallLinkPreview.parse(queryAck: ack(type: "link_query", [BinaryNode(
			tag: "link_query",
			attrs: ["token": "TOKEN", "media": "video", "link_creator": creator, "link_creator_pn": "5511@s.whatsapp.net"],
			content: .nodes([BinaryNode(tag: "waiting_room", attrs: ["enabled": "1", "is_admin": "1"])])
		)]))
		#expect(full.creatorPhone == "5511@s.whatsapp.net")
		#expect(full.isApprovalRequired)
		#expect(full.isAdmin)
	}

	@Test("a join either waits or is in")
	func joinAck() throws {
		let waiting = try CallLinkJoin.parse(ack: ack(type: "link_join", [room()]), link: videoLink)
		#expect(waiting.isInWaitingRoom)
		#expect(waiting.callID == "CID")
		#expect(waiting.group == nil)

		let admitted = try CallLinkJoin.parse(ack: ack(type: "link_join", [roster()]), link: videoLink)
		#expect(!admitted.isInWaitingRoom)
		#expect(admitted.group?.transactionID == 5)

		let both = try CallLinkJoin.parse(ack: ack(type: "link_join", [room(), roster()]), link: videoLink)
		#expect(!both.isInWaitingRoom)
		#expect(both.waitingRoom != nil)
	}

	@Test("a room with nobody letting anyone in is nowhere to wait")
	func disabledRoomAlone() throws {
		#expect(throws: GroupCallStanzaError.self) {
			try CallLinkJoin.parse(ack: ack(type: "link_join", [room(enabled: false)]), link: videoLink)
		}
	}

	@Test("a join's parts have to be about the same link and media")
	func inconsistentJoins() throws {
		#expect(throws: GroupCallStanzaError.self) {
			try CallLinkJoin.parse(ack: ack(type: "link_join", [room(token: "OTHER")]), link: videoLink)
		}
		#expect(throws: GroupCallStanzaError.self) {
			try CallLinkJoin.parse(ack: ack(type: "link_join", [room(media: "audio"), roster()]), link: videoLink)
		}
		#expect(throws: GroupCallStanzaError.self) {
			try CallLinkJoin.parse(ack: ack(type: "link_join", [roster(media: "audio")]), link: videoLink)
		}
		#expect(throws: GroupCallStanzaError.rejected("404")) {
			try CallLinkJoin.parse(ack: ack(type: "link_join", error: "404", []), link: videoLink)
		}
		#expect(throws: GroupCallStanzaError.self) {
			try CallLinkJoin.parse(ack: ack(type: "link_join", []), link: videoLink)
		}
	}

	@Test("a waiting room lists who is waiting")
	func parsesRoom() throws {
		let parsed = try CallWaitingRoom.parse(update: BinaryNode(
			tag: "waiting_room_update",
			attrs: ["call-id": "CID", "call-creator": creator],
			content: .nodes([room(users: [
				BinaryNode(tag: "user", attrs: ["jid": "200002@lid", "user_pn": "5511@s.whatsapp.net", "state": "waiting"])
			])])
		))
		#expect(parsed.users == [CallWaitingRoomUser(jid: "200002@lid", phoneJID: "5511@s.whatsapp.net", state: "waiting")])
		#expect(parsed.transactionID == 4)

		#expect(throws: GroupCallStanzaError.self) {
			try CallWaitingRoom.parse(update: BinaryNode(
				tag: "waiting_room_update",
				attrs: ["call-id": "OTHER", "call-creator": creator],
				content: .nodes([room()])
			))
		}
	}

	@Test("an older waiting room does not replace a newer one, and another link's is refused")
	func waitingRoomOrder() {
		var record = GroupCallRecord(state: GroupCallState(callID: "CID", callCreator: creator))
		func snapshot(_ transaction: UInt32?, link: CallLink? = nil, callID: String = "CID") -> CallWaitingRoom {
			CallWaitingRoom(
				callID: callID,
				callCreator: creator,
				link: link ?? videoLink,
				isEnabled: true,
				isAdmin: false,
				transactionID: transaction
			)
		}

		#expect(record.applyWaitingRoom(snapshot(4)) == .applied)
		#expect(record.applyWaitingRoom(snapshot(4)) == .stale)
		#expect(record.applyWaitingRoom(snapshot(3)) == .stale)
		#expect(record.waitingRoom?.transactionID == 4)
		#expect(record.applyWaitingRoom(snapshot(5)) == .applied)
		#expect(record.applyWaitingRoom(snapshot(6, link: CallLink(token: "OTHER", media: .video))) == .refused)
		#expect(record.applyWaitingRoom(snapshot(6, callID: "OTHER")) == .refused)
		#expect(record.waitingRoom?.transactionID == 5)
	}

	@Test("a screen is captured within the limit, in even numbers")
	func captureSize() throws {
		guard #available(macOS 14.0, *) else {
			return
		}

		let large = CallScreenCapture.captureSize(content: CGSize(width: 1728, height: 1117), scale: 2)
		#expect(large.width == 1280)
		#expect(large.height % 2 == 0)
		#expect(abs(Double(large.height) - 1280 * 1117 / 1728) <= 2)

		let small = CallScreenCapture.captureSize(content: CGSize(width: 321, height: 201), scale: 1)
		#expect(small.width == 322 || small.width == 320)
		#expect(small.height % 2 == 0)

		let tiny = CallScreenCapture.captureSize(content: .zero, scale: 1)
		#expect(tiny.width == 2)
		#expect(tiny.height == 2)
	}
}

@Suite("Call app data")
struct CallAppDataTests {
	/// The bytes the reference captured from a real client.
	private let thumbsUp = Data([0x0a, 0x0a, 0x0a, 0x08, 0x08, 0x01, 0x12, 0x04, 0xf0, 0x9f, 0x91, 0x8d])

	@Test("a reaction matches what a real client sends, and reads back")
	func wireFormat() throws {
		#expect(try CallAppData.encode(transactionID: 1, emoji: "👍") == thumbsUp)
		#expect(try CallAppData.decode(thumbsUp) == [CallAppData.Reaction(transactionID: 1, emoji: "👍")])
	}

	@Test("unknown fields are skipped, and what cannot be read is refused")
	func decoding() throws {
		var extended = try CallAppData.encode(transactionID: 7, emoji: "")
		extended.append(contentsOf: [0x28, 0x01])
		#expect(try CallAppData.decode(extended).first?.transactionID == 7)

		#expect(throws: CallAppDataError.malformed) {
			try CallAppData.decode(Data([0x0a, 0x02, 0x0a]))
		}
		#expect(throws: CallAppDataError.missingTransaction) {
			try CallAppData.encode(transactionID: 0, emoji: "x")
		}
		#expect(throws: CallAppDataError.tooLarge) {
			try CallAppData.encode(transactionID: 1, emoji: String(repeating: "x", count: CallAppData.maxReactionBytes + 1))
		}
		#expect(throws: CallAppDataError.tooLarge) {
			try CallAppData.decode(Data(count: CallAppData.maxPayloadBytes + 1))
		}
		#expect(throws: CallAppDataError.malformed) {
			try CallAppData.decode(Data(repeating: 0x80, count: 10))
		}
		var oversized = Data([0x0a])
		oversized.append(contentsOf: [UInt8](repeating: 0xff, count: 9))
		oversized.append(0x01)
		#expect(throws: CallAppDataError.tooLarge) {
			try CallAppData.decode(oversized)
		}
		// Invalid UTF-8 inside a well-formed message.
		#expect(throws: CallAppDataError.invalidText) {
			try CallAppData.decode(Data([0x0a, 0x07, 0x0a, 0x05, 0x08, 0x01, 0x12, 0x01, 0xff]))
		}
	}
}

@Suite("Call links in the client")
struct CallLinkClientTests {
	private let link = CallLink(token: "TOKEN", media: .video)
	private let creator = "100001:1@lid"

	private struct Harness {
		let transport = MockMessageSendWebSocketTransport()
		let client: WhatsAppClient

		init() async throws {
			let transport = self.transport
			client = WhatsAppClient(transportFactory: { _ in transport })
			await client.useTransport(transport)
		}

		func sent(_ index: Int) async throws -> BinaryNode {
			let frame = try await transport.waitForSentFrame(at: index)
			var codec = NoiseFrameCodec()
			return try BinaryNodeDecoder().decode(codec.decode(frame)[0])
		}

		func acknowledge(_ stanza: BinaryNode, children: [BinaryNode]) async throws {
			let id = try #require(stanza.attrs["id"])
			await client.handleIncomingNode(BinaryNode(
				tag: "ack",
				attrs: ["id": id, "class": "call", "from": "@call"],
				content: .nodes(children)
			))
		}
	}

	private func room(transaction: String = "4", users: [BinaryNode] = []) -> BinaryNode {
		BinaryNode(
			tag: "waiting_room",
			attrs: [
				"call-id": "CID",
				"call-creator": creator,
				"link-token": "TOKEN",
				"media": "video",
				"enabled": "1",
				"is_admin": "0",
				"transaction-id": transaction
			],
			content: .nodes(users)
		)
	}

	private func roomUpdate(from: String = "CID@call", participant: String? = nil, _ room: BinaryNode) -> BinaryNode {
		BinaryNode(
			tag: "call",
			attrs: BinaryNodeAttributes.trimmingUndefined([
				("from", from),
				("id", "s1"),
				("t", "1"),
				("participant", participant)
			]),
			content: .nodes([BinaryNode(
				tag: "waiting_room_update",
				attrs: ["call-id": "CID", "call-creator": creator],
				content: .nodes([room])
			)])
		)
	}

	@Test("creating asks the call service and gives back its link")
	func creates() async throws {
		let harness = try await Harness()
		async let created = harness.client.createCallLink(media: .video)
		let request = try await harness.sent(0)
		#expect(request.attrs["to"] == "@call")
		try await harness.acknowledge(request, children: [
			BinaryNode(tag: "link_create", attrs: ["token": "TOKEN", "media": "video"])
		])
		let result = try await created
		#expect(result == link)
	}

	@Test("a link that comes back as another kind of call is refused")
	func createChangedMedia() async throws {
		let harness = try await Harness()
		async let created = harness.client.createCallLink(media: .video)
		let request = try await harness.sent(0)
		try await harness.acknowledge(request, children: [
			BinaryNode(tag: "link_create", attrs: ["token": "TOKEN", "media": "audio"])
		])
		var refusal: Error?
		do {
			_ = try await created
		} catch {
			refusal = error
		}
		#expect(refusal is GroupCallStanzaError)
	}

	@Test("joining keeps the waiting room for those who ask later")
	func joinsWaiting() async throws {
		let harness = try await Harness()
		async let joined = harness.client.joinCallLink(link)
		let request = try await harness.sent(0)
		#expect(request.firstChild(named: "link_join")?.attrs["token"] == "TOKEN")
		try await harness.acknowledge(request, children: [room()])

		let join = try await joined
		#expect(join.isInWaitingRoom)
		#expect(join.callID == "CID")
		#expect(join.callCreator == creator)
		#expect(join.waitingRoom?.transactionID == 4)
	}

	@Test("a newer waiting room that overtook the join's ack stands")
	func overtakenJoin() async throws {
		let harness = try await Harness()
		async let joined = harness.client.joinCallLink(link)
		let request = try await harness.sent(0)
		_ = await harness.client.handleCallNode(roomUpdate(room(transaction: "9")))
		try await harness.acknowledge(request, children: [room(transaction: "4")])

		let join = try await joined
		#expect(join.waitingRoom?.transactionID == 9)
	}

	@Test("a waiting room reaches the app, with its typed ack")
	func roomEvent() async throws {
		let harness = try await Harness()
		let events = await harness.client.events
		_ = await harness.client.handleCallNode(roomUpdate(room(users: [
			BinaryNode(tag: "user", attrs: ["jid": "200002@lid", "state": "waiting"])
		])))

		let ack = try await harness.sent(0)
		#expect(ack.attrs["type"] == "waiting_room_update")

		for await event in events {
			if case let .call(calls) = event, let call = calls.first(where: { $0.status == .waitingRoom }) {
				#expect(call.waitingRoom?.users.first?.jid == "200002@lid")
				#expect(call.isVideo == true)
				break
			}
		}
	}

	@Test("only the creator or the service can write a waiting room")
	func roomWriters() async throws {
		let harness = try await Harness()
		_ = await harness.client.handleCallNode(roomUpdate(participant: "900009:1@lid", room()))
		#expect(await harness.client.groupCalls["CID"]?.waitingRoom == nil)

		_ = await harness.client.handleCallNode(roomUpdate(participant: creator, room()))
		#expect(await harness.client.groupCalls["CID"]?.waitingRoom?.transactionID == 4)
	}

	@Test("the call service itself can write a waiting room, before there is any call to come from")
	func serviceWritesRoom() async throws {
		let harness = try await Harness()
		_ = await harness.client.handleCallNode(roomUpdate(from: "@call", room()))
		#expect(await harness.client.groupCalls["CID"]?.waitingRoom?.transactionID == 4)
	}

	@Test("a screen share reaches the app, saying which way it went")
	func screenShareEvent() async throws {
		let harness = try await Harness()
		let events = await harness.client.events
		_ = await harness.client.handleCallNode(BinaryNode(
			tag: "call",
			attrs: ["from": "CID@call", "participant": "200002:1@lid", "id": "s1", "t": "1"],
			content: .nodes([BinaryNode(
				tag: "screen_share",
				attrs: ["call-id": "CID", "call-creator": creator, "screenshare_state": "1", "version": "2"]
			)])
		))

		for await event in events {
			if case let .call(calls) = event, let call = calls.first(where: { $0.status == .screenShare }) {
				#expect(call.screenShareState == .started)
				#expect(call.senderJID == "200002:1@lid")
				break
			}
		}
	}
}

@Suite("Moving a call's video to a new encoder")
struct CallVideoSourceTests {
	@Test("a new encoder's clock goes on from where it is told to")
	func firstTimestamp() async throws {
		let (frames, continuation) = AsyncStream<CallEncodedVideoFrame>.makeStream()
		let encoder = try CallVideoEncoder(width: 64, height: 64, bitrate: 200_000, firstTimestamp: 900_000) { frame in
			continuation.yield(frame)
		}
		var pixelBuffer: CVPixelBuffer?
		CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pixelBuffer)
		let picture = try #require(pixelBuffer)
		encoder.encode(picture, presentationTime: CMTime(value: 1, timescale: 1))

		var iterator = frames.makeAsyncIterator()
		let first = await iterator.next()
		#expect(first?.timestamp == 900_000)
		#expect(first?.isKeyframe == true)
		encoder.invalidate()
	}
}
