import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import WhatsAppWeb

private func hex(_ string: String) -> Data {
	var bytes = [UInt8]()
	var index = string.startIndex
	while index < string.endIndex {
		let next = string.index(index, offsetBy: 2)
		bytes.append(UInt8(string[index..<next], radix: 16)!)
		index = next
	}
	return Data(bytes)
}

private func annexB(_ nals: [[UInt8]]) -> Data {
	Data(nals.flatMap { [0, 0, 0, 1] + $0 })
}

private let sps: [UInt8] = [0x67, 0x42, 0xc0, 0x1f, 0xda]
private let pps: [UInt8] = [0x68, 0xce, 0x06, 0xe2]

private func slice(type: UInt8, size: Int, seed: UInt8 = 0x11) -> [UInt8] {
	[0x60 | type] + (0..<size).map { UInt8(truncatingIfNeeded: Int(seed) &+ $0) | 0x80 }
}

@Suite("Call video RTP header")
struct CallVideoRTPHeaderTests {
	@Test("matches a keyframe header captured from Android")
	func keyframeCapture() {
		let header = CallVideoRTPHeader(
			marker: true,
			sequenceNumber: 1,
			timestamp: 114_120,
			ssrc: 0x49c5_fb8c,
			frameInfo: 0x09,
			shortOffset: 29,
			transportSequence: 0x0c3f
		)
		#expect(header.encoded() == hex("90e100010001bdc849c5fb8cdebe0003300951000061001d910c3f00"))
	}

	@Test("matches a delta header captured from Android")
	func deltaCapture() {
		let header = CallVideoRTPHeader(
			marker: true,
			sequenceNumber: 7,
			timestamp: 0x0002_2ea2,
			ssrc: 0x9b19_59f0,
			frameInfo: 0x01,
			shortOffset: 36,
			transportSequence: 0x0a6a
		)
		#expect(header.encoded() == hex("90e1000700022ea29b1959f0debe00033001510000610024910a6a00"))
	}

	@Test("reads frame information and the time offset back from a captured header")
	func readsExtensions() {
		let elements = CallRTPExtensionElements(packet: hex("90e100010001bdc849c5fb8cdebe0003300951000061001d910c3f00"))
		#expect(elements.frameInfo == 0x09)
		#expect(elements.timeOffsetMs == 29)
		#expect(elements.audioOffset == nil)
	}

	@Test("the generic parser sees 28 bytes of header")
	func headerLength() {
		#expect(CallRTPHeader.length(of: hex("90e100010001bdc849c5fb8cdebe0003300951000061001d910c3f00")) == 28)
	}

	@Test("splits a carried audio packet, and padding ends the media part")
	func splitsCarriedAudio() {
		// P and X set; one element with id 7 saying the media part is 5 bytes.
		let header = Data([0xb0, 0x61, 0, 1, 0, 0, 0, 1, 0, 0, 0, 2, 0xde, 0xbe, 0, 1, 0x71, 0, 5, 0])
		let payload = Data([1, 2, 3, 0xaa, 2, 9, 9])
		let (media, audio) = CallRTPExtensionElements.splitCarriedAudio(packet: header, payload: payload)
		#expect(media == Data([1, 2, 3]))
		#expect(audio == Data([9, 9]))
	}

	@Test("an offset that leaves no audio behind is not a piggyback")
	func offsetPastPayload() {
		let header = Data([0x90, 0x61, 0, 1, 0, 0, 0, 1, 0, 0, 0, 2, 0xde, 0xbe, 0, 1, 0x71, 0, 9, 0])
		let payload = Data([1, 2, 3])
		let (media, audio) = CallRTPExtensionElements.splitCarriedAudio(packet: header, payload: payload)
		#expect(media == payload)
		#expect(audio == nil)
	}
}

@Suite("Call H.264 packetization")
struct CallH264Tests {
	@Test("splits Annex-B with both start code lengths")
	func splits() {
		let data = Data([0, 0, 0, 1, 0x67, 1, 0, 0, 1, 0x68, 2, 0, 0, 0, 1, 0x65, 3])
		#expect(CallH264.splitAnnexB(data) == [Data([0x67, 1]), Data([0x68, 2]), Data([0x65, 3])])
	}

	@Test("drops delimiters and leading SEI, and aggregates parameter sets")
	func dropsAndAggregates() {
		let idr = slice(type: 5, size: 100)
		let unit = annexB([[0x09, 0xf0], [0x06, 1, 2], sps, pps, idr])
		let payloads = CallH264.packetize(unit)

		#expect(payloads.count == 2)
		let aggregate = [UInt8](payloads[0])
		#expect(aggregate[0] & 0x1f == CallH264.typeSTAPA)
		#expect(aggregate[0] & 0x60 == 0x60)
		#expect(Array(aggregate[1..<3]) == [0, UInt8(sps.count)])
		#expect(Array(aggregate[3..<(3 + sps.count)]) == sps)
		#expect([UInt8](payloads[1]) == idr)
	}

	@Test("fragments an oversized slice evenly, with start and end bits")
	func fragments() {
		let nal = slice(type: 5, size: 3_000)
		let payloads = CallH264.packetize(annexB([nal]))

		#expect(payloads.count == 4)
		let sizes = payloads.map(\.count)
		#expect(sizes.max()! - sizes.min()! <= 1)
		#expect(sizes.max()! <= CallH264.singleNALMax)
		#expect(payloads.allSatisfy { $0[0] & 0x1f == CallH264.typeFUA && $0[1] & 0x1f == 5 })
		#expect(payloads[0][1] & 0x80 != 0)
		#expect(payloads[0][1] & 0x40 == 0)
		#expect(payloads[3][1] & 0x80 == 0)
		#expect(payloads[3][1] & 0x40 != 0)
	}

	private func feed(_ payloads: [Data], from sequence: UInt16 = 100, timestamp: UInt32 = 9_000, into depacketizer: inout CallH264Depacketizer) -> [CallH264Depacketizer.AccessUnit] {
		var units = [CallH264Depacketizer.AccessUnit]()
		for (index, payload) in payloads.enumerated() {
			units += depacketizer.push(
				sequence: sequence &+ UInt16(index),
				timestamp: timestamp,
				payload: payload,
				marker: index == payloads.count - 1
			)
		}
		return units
	}

	@Test("rebuilds what it packetized")
	func roundTrip() {
		let unit = annexB([sps, pps, slice(type: 5, size: 5_000), slice(type: 5, size: 300)])
		var depacketizer = CallH264Depacketizer()
		let units = feed(CallH264.packetize(unit), into: &depacketizer)

		#expect(units == [.init(timestamp: 9_000, data: unit)])
	}

	@Test("drops a NAL that lost a fragment, keeping the rest of the picture")
	func lostFragment() {
		let whole = slice(type: 1, size: 3_000)
		let other = slice(type: 1, size: 200)
		var payloads = CallH264.packetize(annexB([other, whole, other]))
		payloads.remove(at: 2)
		var sequence: UInt16 = 0
		var depacketizer = CallH264Depacketizer()
		var units = [CallH264Depacketizer.AccessUnit]()
		for (index, payload) in payloads.enumerated() {
			// The gap left by the removed fragment.
			if index == 2 { sequence &+= 1 }
			units += depacketizer.push(
				sequence: sequence,
				timestamp: 90,
				payload: payload,
				marker: index == payloads.count - 1
			)
			sequence &+= 1
		}

		#expect(units == [.init(timestamp: 90, data: annexB([other, other]))])
	}

	@Test("a lost marker closes the picture when the next one begins")
	func lostMarker() {
		let first = slice(type: 1, size: 50)
		let second = slice(type: 1, size: 60)
		var depacketizer = CallH264Depacketizer()

		let none = depacketizer.push(sequence: 1, timestamp: 100, payload: Data(first), marker: false)
		#expect(none.isEmpty)
		let units = depacketizer.push(sequence: 2, timestamp: 200, payload: Data(second), marker: true)

		#expect(units == [
			.init(timestamp: 100, data: annexB([first])),
			.init(timestamp: 200, data: annexB([second]))
		])
	}

	@Test("a packet of a picture already past is discarded")
	func stalePacket() {
		let first = slice(type: 1, size: 50)
		var depacketizer = CallH264Depacketizer()
		_ = depacketizer.push(sequence: 5, timestamp: 200, payload: Data(first), marker: true)

		let older = depacketizer.push(sequence: 4, timestamp: 100, payload: Data(first), marker: true)
		#expect(older.isEmpty)
		#expect(depacketizer.lastPacketTimestamp == nil)
		let closed = depacketizer.push(sequence: 6, timestamp: 200, payload: Data(first), marker: true)
		#expect(closed.isEmpty)
	}

	@Test("tells apart two pictures an iPhone sends on one timestamp, by their offsets")
	func sharedTimestamp() {
		let first = slice(type: 1, size: 50)
		let second = slice(type: 1, size: 60)
		var depacketizer = CallH264Depacketizer()

		let one = depacketizer.push(sequence: 1, timestamp: 900, offsetMs: 10, payload: Data(first), marker: true)
		let two = depacketizer.push(sequence: 2, timestamp: 900, offsetMs: 77, payload: Data(second), marker: true)

		#expect(one == [.init(timestamp: 900, data: annexB([first]))])
		#expect(two == [.init(timestamp: 900 + 67 * 90, data: annexB([second]))])
	}

	@Test("survives truncated aggregates and fragments")
	func malformed() {
		var depacketizer = CallH264Depacketizer()
		let inputs: [[UInt8]] = [[0x18, 0, 200, 1], [0x1c], [], [0x1e, 1]]
		for (index, input) in inputs.enumerated() {
			let units = depacketizer.push(sequence: UInt16(index), timestamp: UInt32(index), payload: Data(input), marker: true)
			#expect(units.isEmpty)
		}
	}
}

@Suite("Call video pipeline")
struct CallVideoPipelineTests {
	private let key = Data((0..<32).map(UInt8.init))
	private let alice = "111:0@lid"
	private let bob = "222:0@lid"

	private func pipeline(from: String, to: String) throws -> CallVideoPipeline {
		try CallVideoPipeline(callKey: key, selfParticipantID: from, peerParticipantID: to, ssrc: 0x1234_5678)
	}

	private func packets(
		_ unit: Data,
		through sender: inout CallVideoPipeline,
		timestamp: UInt32,
		frameInfo: UInt8 = 0
	) throws -> [Data] {
		let payloads = CallH264.packetize(unit)
		return try payloads.enumerated().map { index, payload in
			try sender.protect(
				payload,
				marker: index == payloads.count - 1,
				timestamp: timestamp,
				frameInfo: frameInfo,
				shortOffset: 5
			).packet
		}
	}

	@Test("a picture crosses, and only the right keys read it")
	func roundTrip() throws {
		var sender = try pipeline(from: alice, to: bob)
		var receiver = try pipeline(from: bob, to: alice)
		var stranger = try pipeline(from: bob, to: "333:0@lid")
		let unit = annexB([sps, pps, slice(type: 5, size: 4_000)])

		var frames = [CallVideoFrame]()
		for packet in try packets(unit, through: &sender, timestamp: 4_500, frameInfo: CallVideoRTPHeader.frameInfoIDR | 1) {
			#expect(packet.count <= CallVideoRTPHeader.length + CallH264.singleNALMax + CallMediaCrypto.warpTagLength)
			frames += try receiver.unprotect(packet).frames
			#expect(throws: CallAudioPipeline.ReceiveError.authenticationFailed) {
				_ = try stranger.unprotect(packet)
			}
		}

		#expect(frames == [CallVideoFrame(data: unit, timestamp: 4_500, isKeyframe: true, orientation: 1)])
		#expect(receiver.inboundSSRC == 0x1234_5678)
	}

	@Test("a replayed packet is refused")
	func replay() throws {
		var sender = try pipeline(from: alice, to: bob)
		var receiver = try pipeline(from: bob, to: alice)
		let packet = try packets(annexB([slice(type: 1, size: 40)]), through: &sender, timestamp: 1)[0]

		_ = try receiver.unprotect(packet)
		#expect(throws: CallAudioPipeline.ReceiveError.replayed) {
			_ = try receiver.unprotect(packet)
		}
	}

	@Test("counts the packets missing before one that arrived")
	func countsLoss() throws {
		var sender = try pipeline(from: alice, to: bob)
		var receiver = try pipeline(from: bob, to: alice)
		let sent = try (0..<5).flatMap { try packets(annexB([slice(type: 1, size: 40)]), through: &sender, timestamp: UInt32($0) * 4_500) }

		var lost = [UInt16]()
		for index in [0, 3, 1, 4] {
			lost.append(try receiver.unprotect(sent[index]).lost)
		}
		#expect(lost == [0, 2, 0, 0])
	}

	@Test("a stream that took over keeps a straggler of the old one from breaking it")
	func straggler() throws {
		var oldStream = try CallVideoPipeline(callKey: key, selfParticipantID: alice, peerParticipantID: bob, ssrc: 1)
		var newStream = try CallVideoPipeline(callKey: key, selfParticipantID: alice, peerParticipantID: bob, ssrc: 2)
		var receiver = try pipeline(from: bob, to: alice)
		let unit = annexB([slice(type: 1, size: 40)])

		_ = try receiver.unprotect(try packets(unit, through: &oldStream, timestamp: 100)[0])
		let taken = try receiver.unprotect(try packets(unit, through: &newStream, timestamp: 1)[0])
		#expect(taken.frames.count == 1)
		let late = try receiver.unprotect(try packets(unit, through: &oldStream, timestamp: 200)[0])

		#expect(!late.isCurrentStream)
		#expect(late.frames.isEmpty)
		#expect(receiver.inboundSSRC == 2)
	}

	@Test("carried audio goes through the audio stream's replay check")
	func carriedAudioReplay() throws {
		var audio = try CallAudioPipeline(callKey: key, selfParticipantID: bob, peerParticipantID: alice, ssrc: 7)
		let packet = CallRTPHeader(sequenceNumber: 9, timestamp: 960, ssrc: 77).encoded() + Data([1, 2, 3])

		let first = audio.acceptCarried(packet)
		let repeated = audio.acceptCarried(packet)
		#expect(first?.payload == Data([1, 2, 3]))
		#expect(repeated == nil)

		let notAudio = CallRTPHeader(payloadType: 97, sequenceNumber: 10, timestamp: 960, ssrc: 77).encoded() + Data([1])
		let refused = audio.acceptCarried(notAudio)
		#expect(refused == nil)
	}
}

@Suite("Call RTCP")
struct CallRTCPTests {
	private let keys = CallSRTPKeys(
		cipherKey: Data(repeating: 1, count: 16),
		salt: Data(repeating: 2, count: 14),
		authKey: Data(repeating: 3, count: 20)
	)

	@Test("a PLI has the native video profile's first byte")
	func pli() {
		let packet = CallRTCP.pictureLossIndication(senderSSRC: 0x1111_2222, mediaSSRC: 0x5555_6666)
		#expect(packet == hex("91ce000211112222" + "55556666"))

		let feedback = CallRTCP.parse(packet)?.feedback ?? []
		#expect(feedback.first?.format == 1)
		#expect(feedback.first?.mediaSSRC == 0x5555_6666)
		#expect(CallRTCP.requestsKeyframe(feedback, ssrc: 0x5555_6666))
		#expect(!CallRTCP.requestsKeyframe(feedback, ssrc: 1))
	}

	@Test("a FIR names its target in the control information")
	func fir() {
		let packet = hex("84ce0004" + "11112222" + "00000000" + "55556666" + "07000000")
		let feedback = CallRTCP.parse(packet)?.feedback ?? []
		#expect(CallRTCP.requestsKeyframe(feedback, ssrc: 0x5555_6666))
	}

	@Test("a NACK expands its bitmask")
	func nack() {
		let packet = hex("91cd0003" + "11112222" + "55556666" + "00640005")
		let feedback = CallRTCP.parse(packet)?.feedback ?? []
		#expect(CallRTCP.nackedSequences(feedback, ssrc: 0x5555_6666) == [100, 101, 103])
		#expect(CallRTCP.nackedSequences(feedback, ssrc: 1).isEmpty)
	}

	@Test("a report block survives the native layout, with and without its extension")
	func reportBlocks() throws {
		let report = CallRTCP.ReceptionReport(
			ssrc: 0xabcd,
			fractionLost: 25,
			cumulativeLost: 3,
			extendedHighestSequence: 70_000,
			jitter: 9,
			lastSenderReport: 1,
			delaySinceLastSenderReport: 2,
			bytesReceived: 1_000,
			receiveRateBps: 8_000
		)
		let packet = CallRTCP.senderReport(
			ssrc: 42,
			rtpTimestamp: 90_000,
			packetsSent: 10,
			octetsSent: 1_000,
			wallclockMs: 1_700_000_000_000,
			cname: CallRTCP.cname(ssrc: 42, callKey: Data(repeating: 1, count: 32)),
			report: report
		)
		let parsed = try #require(CallRTCP.parse(packet))
		#expect(parsed.reportBlocks == [CallRTCP.ReportBlock(ssrc: 0xabcd, fractionLost: 25)])
		#expect(parsed.senderTimings.first?.ssrc == 42)

		let bytes = [UInt8](packet)
		#expect(bytes[0] == 0x91)
		#expect(Int(bytes[3]) == (28 + 24 + 24) / 4 - 1)
		#expect(bytes.count == 28 + 24 + 24 + 32)
		#expect(bytes[28 + 24 + 24] == 0x91)
		#expect(bytes[28 + 24 + 24 + 1] == 202)

		let plainRFC = Data(bytes[0..<4]) + Data(bytes[4..<28]) + Data(bytes[28..<52])
		var rfc = [UInt8](plainRFC)
		rfc[0] = 0x81
		rfc[3] = UInt8(52 / 4 - 1)
		#expect(CallRTCP.parse(Data(rfc))?.reportBlocks.first?.fractionLost == 25)
	}

	@Test("a CNAME has WhatsApp's shape")
	func cname() {
		let value = CallRTCP.cname(ssrc: 1, callKey: Data(repeating: 9, count: 32))
		#expect(value.count == CallRTCP.cnameLength)
		let text = String(decoding: value, as: UTF8.self)
		#expect(text.dropFirst(5).hasPrefix("@pj"))
		#expect(text.hasSuffix(".org"))
	}

	@Test("SRTCP round trips and rejects tampering")
	func srtcp() throws {
		let plain = CallRTCP.pictureLossIndication(senderSSRC: 5, mediaSSRC: 6)
		let protected = try CallMediaCrypto.protectRTCP(plain, keys: keys, senderSSRC: 5, index: 3)

		let opened = try #require(CallMediaCrypto.unprotectRTCP(protected, keys: keys, senderSSRC: 5))
		#expect(opened.rtcp == plain)
		#expect(opened.index == 3)

		var tampered = protected
		tampered[9] ^= 1
		#expect(CallMediaCrypto.unprotectRTCP(tampered, keys: keys, senderSSRC: 5) == nil)
	}

	@Test("the SRTCP replay window refuses repeats and accepts reordering")
	func replayWindow() {
		var window = CallSRTCPReplayWindow()
		let steps: [(sender: UInt32, index: UInt32)] = [(1, 10), (1, 10), (1, 12), (1, 11), (1, 11), (2, 1)]
		let accepted = steps.map { window.accept(sender: $0.sender, index: $0.index) }
		#expect(accepted == [true, false, true, true, false, true])
	}

	@Test("reception stats report loss since the previous report")
	func receptionStats() throws {
		var stats = CallRTPReceptionStats()
		for sequence: UInt16 in [10, 11, 13, 14] {
			stats.observe(ssrc: 9, sequence: sequence, timestamp: 0, arrivalMs: 1_000, payload: 100)
		}
		let firstReport = stats.report(nowMs: 1_000)
		let first = try #require(firstReport)
		#expect(first.fractionLost == 51)
		#expect(first.cumulativeLost == 1)
		#expect(first.extendedHighestSequence == 14)
		#expect(first.bytesReceived == 400)

		stats.observe(ssrc: 9, sequence: 15, timestamp: 0, arrivalMs: 2_000, payload: 100)
		let secondReport = stats.report(nowMs: 2_000)
		let second = try #require(secondReport)
		#expect(second.fractionLost == 0)
		#expect(second.receiveRateBps == 800)
	}
}

@Suite("Call video stanzas")
struct CallVideoStanzaTests {
	private func action(_ node: BinaryNode) throws -> BinaryNode {
		guard case let .nodes(children)? = node.content, let first = children.first else {
			throw CallSessionError.notRunning
		}
		return first
	}

	private func tags(_ node: BinaryNode) -> [String] {
		guard case let .nodes(children)? = node.content else {
			return []
		}
		return children.map(\.tag)
	}

	@Test("a video offer capability clears MLow from the video blob")
	func capability() {
		#expect(CallCapability.videoOffer == Data([0x01, 0x05, 0xf7, 0x09, 0xe0, 0xbb, 0x53]))
		#expect(CallCapability.standardOpusVideoOffer == Data([0x01, 0x05, 0xf7, 0x09, 0xe0, 0x3b, 0x53]))
	}

	@Test("an offer places video after audio, with the attributes WhatsApp's reader takes")
	func offer() throws {
		let offer = try action(CallStanzaBuilder.offer(
			callID: "C",
			to: "1@lid",
			callCreator: "2@lid",
			stanzaID: "S",
			deviceKeys: [CallOfferDeviceKey(deviceJID: "1:1@lid", ciphertext: Data([1]), encryptionType: "msg")],
			capability: CallCapability.standardOpusVideoOffer,
			video: true
		))
		#expect(tags(offer) == ["audio", "video", "net", "capability", "enc", "encopt"])

		let video = try #require(offer.firstChild(named: "video"))
		#expect(video.attrs["enc"] == "h.264")
		#expect(video.attrs["dec"] == "H264")
		#expect(video.attrs["screen_width"] == "0")
		#expect(video.attrs["screen_height"] == "0")
		#expect(video.attrs["device_orientation"] == "0")
	}

	@Test("a voice offer has no video child")
	func voiceOffer() throws {
		let offer = try action(CallStanzaBuilder.offer(
			callID: "C",
			to: "1@lid",
			callCreator: "2@lid",
			stanzaID: "S",
			deviceKeys: []
		))
		#expect(offer.firstChild(named: "video") == nil)
	}

	@Test("a video preaccept advertises the decoder, under the offer's capability")
	func preaccept() throws {
		let preaccept = try action(CallStanzaBuilder.preaccept(
			callID: "C",
			to: "1@lid",
			callCreator: "2@lid",
			stanzaID: "S",
			video: true
		))
		#expect(tags(preaccept) == ["audio", "video", "encopt", "capability"])
		#expect(preaccept.firstChild(named: "video")?.attrs["dec"] == "H264")
		#expect(preaccept.firstChild(named: "video")?.attrs["enc"] == nil)
		if case let .data(blob)? = preaccept.firstChild(named: "capability")?.content {
			#expect(blob == CallCapability.standardOpusOffer)
		} else {
			Issue.record("capability without a blob")
		}
	}

	@Test("a voice preaccept keeps its own capability")
	func voicePreaccept() throws {
		let preaccept = try action(CallStanzaBuilder.preaccept(callID: "C", to: "1", callCreator: "2", stanzaID: "S"))
		if case let .data(blob)? = preaccept.firstChild(named: "capability")?.content {
			#expect(blob == CallCapability.standardOpusPreaccept)
		} else {
			Issue.record("capability without a blob")
		}
	}

	@Test("a video accept has no capability and mirrors the offer's metadata")
	func accept() throws {
		let accept = try action(CallStanzaBuilder.accept(
			callID: "C",
			to: "1@lid",
			callCreator: "2@lid",
			stanzaID: "S",
			video: true,
			peerMetadata: CallPeerMetadata(abTestBucket: "b", abTestBucketIDList: nil)
		))
		#expect(tags(accept) == ["audio", "video", "net", "encopt", "metadata", "voip_settings"])
		#expect(accept.firstChild(named: "metadata")?.attrs["peer_abtest_bucket"] == "b")
		#expect(accept.firstChild(named: "video")?.attrs["dec"] == "H264")
	}

	@Test("a voice accept keeps its capability and has no video")
	func voiceAccept() throws {
		let accept = try action(CallStanzaBuilder.accept(callID: "C", to: "1", callCreator: "2", stanzaID: "S"))
		#expect(tags(accept) == ["audio", "net", "encopt", "capability", "voip_settings"])
	}

	@Test("only an upgrade request names voip_settings")
	func videoState() throws {
		let request = try action(CallStanzaBuilder.videoState(
			callID: "C",
			to: "1@lid",
			callCreator: "2@lid",
			stanzaID: "S",
			state: .upgradeRequestV2,
			decoders: "H264",
			deviceOrientation: "0"
		))
		#expect(request.tag == "video")
		#expect(request.attrs["state"] == "11")
		#expect(request.attrs["voip_settings"] == "video")
		#expect(request.attrs["dec"] == "H264")

		let stopped = try action(CallStanzaBuilder.videoState(
			callID: "C",
			to: "1@lid",
			callCreator: "2@lid",
			stanzaID: "S",
			state: .stopped
		))
		#expect(stopped.attrs["state"] == "6")
		#expect(stopped.attrs["voip_settings"] == nil)
		#expect(stopped.attrs["dec"] == nil)
		#expect(stopped.attrs["device_orientation"] == nil)
	}

	@Test("a video stanza maps to its own update type")
	func status() {
		let node = BinaryNode(tag: "video", attrs: ["call-id": "C", "state": "1"])
		#expect(IncomingCallStatusMapper.status(from: node) == .video)
	}
}

/// Two legs of a call in memory, with loss that a test can program.
private actor VideoFakeRelay {
	private var legs: [Int: AsyncStream<Data>.Continuation] = [:]
	private var dropNext: ((Data) -> Bool)?
	private(set) var forwarded = [Data]()

	func register(_ leg: Int, _ continuation: AsyncStream<Data>.Continuation) {
		legs[leg] = continuation
	}

	func drop(when predicate: @escaping (Data) -> Bool) {
		dropNext = predicate
	}

	func receive(from leg: Int, _ message: Data) {
		if CallSTUN.isSTUN(message) {
			if CallSTUN.messageType(message) == CallSTUN.allocateRequest {
				let transaction = CallSTUN.transactionID(message) ?? Data(count: 12)
				legs[leg]?.yield(CallSTUN.encode(type: CallSTUN.allocateSuccess, transactionID: transaction))
			}
			return
		}

		if let dropNext, dropNext(message) {
			self.dropNext = nil
			return
		}
		forwarded.append(message)
		legs[1 - leg]?.yield(message)
	}
}

private final class VideoFakeLink: CallRelayLink, @unchecked Sendable {
	let messages: AsyncStream<Data>
	private let continuation: AsyncStream<Data>.Continuation
	private let relay: VideoFakeRelay
	private let leg: Int

	init(relay: VideoFakeRelay, leg: Int) async {
		(messages, continuation) = AsyncStream.makeStream()
		self.relay = relay
		self.leg = leg
		await relay.register(leg, continuation)
	}

	func open() async throws {}

	func send(_ message: Data) async throws {
		await relay.receive(from: leg, message)
	}

	func close() async {
		continuation.finish()
	}
}

@Suite("Call session video", .timeLimit(.minutes(1)))
struct CallSessionVideoTests {
	private let callKey = Data((0..<32).map(UInt8.init))
	private let aliceLID = "111111111111111:0@lid"
	private let bobLID = "222222222222222:0@lid"

	private var relayData: CallRelayData {
		CallRelayData(
			relayKeyASCII: Data("relay-secret-key".utf8),
			relayTokens: [Data([1, 2, 3, 4])],
			authTokens: [],
			endpoints: [
				CallRelayEndpoint(
					relayID: 1,
					relayName: "gru1",
					tokenID: 0,
					authTokenID: 1,
					isFNA: false,
					ipv4Bytes: nil,
					addresses: [CallRelayAddress(protocolID: 0, ipv4: "157.240.226.133", ipv6: nil, port: 3478)],
					clientToRelayRTTMs: nil
				)
			]
		)
	}

	private func legs() async throws -> (alice: CallSession, bob: CallSession, relay: VideoFakeRelay) {
		let relay = VideoFakeRelay()
		func configuration(_ me: String, _ peer: String) -> CallSession.Configuration {
			CallSession.Configuration(
				callID: "00112233445566778899AABBCCDDEEFF",
				selfParticipantID: me,
				peerParticipantID: peer,
				callKey: callKey,
				relay: relayData
			)
		}
		let alice = try CallSession(
			configuration: configuration(aliceLID, bobLID),
			link: await VideoFakeLink(relay: relay, leg: 0)
		)
		let bob = try CallSession(
			configuration: configuration(bobLID, aliceLID),
			link: await VideoFakeLink(relay: relay, leg: 1)
		)
		try await alice.start()
		try await bob.start()
		return (alice, bob, relay)
	}

	private func first(_ stream: AsyncStream<CallVideoFrame>, count: Int) -> Task<[CallVideoFrame], Never> {
		Task {
			var frames = [CallVideoFrame]()
			for await frame in stream {
				frames.append(frame)
				if frames.count == count {
					break
				}
			}
			return frames
		}
	}

	private func waitUntil(_ condition: () async -> Bool) async -> Bool {
		for _ in 0..<300 {
			if await condition() {
				return true
			}
			try? await Task.sleep(for: .milliseconds(10))
		}
		return false
	}

	@Test("pictures cross between legs, starting from an IDR")
	func crosses() async throws {
		let (alice, bob, _) = try await legs()
		let reader = first(bob.receivedVideo, count: 2)
		await alice.setVideoSending(true)

		let delta = annexB([slice(type: 1, size: 2_000)])
		let idr = annexB([sps, pps, slice(type: 5, size: 6_000)])
		try await alice.sendVideo(delta, timestamp: 0)
		#expect(await alice.videoFramesSent == 0)

		try await alice.sendVideo(idr, timestamp: 4_500, capturedAt: .now)
		try await alice.sendVideo(delta, timestamp: 9_000, capturedAt: .now)
		let frames = await reader.value

		#expect(frames.map(\.data) == [idr, delta])
		#expect(frames.map(\.isKeyframe) == [true, false])
		await alice.stop()
		await bob.stop()
	}

	@Test("sends nothing until it is allowed to")
	func gated() async throws {
		let (alice, bob, relay) = try await legs()
		try await alice.sendVideo(annexB([sps, pps, slice(type: 5, size: 100)]), timestamp: 0)
		#expect(await relay.forwarded.isEmpty)
		await alice.stop()
		await bob.stop()
	}

	@Test("a lost packet makes the receiver ask for a keyframe, and the sender's encoder is told")
	func lossAsksForKeyframe() async throws {
		let (alice, bob, relay) = try await legs()
		let events = Task { () -> Bool in
			var count = 0
			for await event in alice.videoSendEvents where event == .keyframeNeeded {
				count += 1
				if count == 2 {
					return true
				}
			}
			return false
		}
		await alice.setVideoSending(true)

		let idr = annexB([sps, pps, slice(type: 5, size: 3_000)])
		try await alice.sendVideo(idr, timestamp: 0)
		var armed = false
		await relay.drop { _ in
			defer { armed = true }
			return !armed
		}
		let delta = annexB([slice(type: 1, size: 100)])
		for index in 1...3 {
			try await alice.sendVideo(delta, timestamp: UInt32(index) * 4_500)
		}

		#expect(await waitUntil { await bob.keyframesRequestedFromPeer == 1 })
		#expect(await waitUntil { await alice.keyframesRequestedByPeer == 1 })
		#expect(await events.value)

		// With a request open only an IDR goes out.
		let sentBefore = await alice.videoFramesSent
		try await alice.sendVideo(delta, timestamp: 40_000)
		#expect(await alice.videoFramesSent == sentBefore)
		try await alice.sendVideo(idr, timestamp: 50_000)
		#expect(await alice.videoFramesSent == sentBefore + 1)
		await alice.stop()
		await bob.stop()
	}

	@Test("a peer's NACK is answered from what was sent, a limited number of times")
	func answersNACK() async throws {
		let (alice, bob, relay) = try await legs()
		await alice.setVideoSending(true)
		try await alice.sendVideo(annexB([sps, pps, slice(type: 5, size: 100)]), timestamp: 0)
		let forwarded = await relay.forwarded.count
		let ssrc = CallRelayAllocate.videoSSRC(
			callID: "00112233445566778899AABBCCDDEEFF",
			participantID: aliceLID
		)
		let bobSSRC = CallRelayAllocate.videoSSRC(callID: "00112233445566778899AABBCCDDEEFF", participantID: bobLID)
		let keys = try CallMediaCrypto.deriveRTCPKeys(callKey: callKey, participantID: bobLID)
		let nack = Data([0x91, 205, 0, 3]) + bytes(bobSSRC) + bytes(ssrc) + Data([0, 0, 0, 0])

		for index in 1...4 {
			let protected = try CallMediaCrypto.protectRTCP(nack, keys: keys, senderSSRC: bobSSRC, index: UInt32(index))
			await relay.receive(from: 1, protected)
		}

		#expect(await waitUntil { await alice.videoPacketsResent == CallSessionVideoTests.expectedResends })
		try? await Task.sleep(for: .milliseconds(50))
		#expect(await alice.videoPacketsResent == CallSessionVideoTests.expectedResends)
		#expect(await relay.forwarded.count >= forwarded + CallSessionVideoTests.expectedResends)
		await alice.stop()
		await bob.stop()
	}

	private static let expectedResends = 2

	private func bytes(_ value: UInt32) -> Data {
		withUnsafeBytes(of: value.bigEndian) { Data($0) }
	}

	@Test("reported loss lowers the bitrate the encoder is told to use")
	func lossLowersBitrate() async throws {
		let (alice, bob, relay) = try await legs()
		let reader = Task { () -> Int? in
			for await event in alice.videoSendEvents {
				if case let .targetBitrate(value) = event {
					return value
				}
			}
			return nil
		}
		let ssrc = CallRelayAllocate.videoSSRC(callID: "00112233445566778899AABBCCDDEEFF", participantID: aliceLID)
		let bobSSRC = CallRelayAllocate.videoSSRC(callID: "00112233445566778899AABBCCDDEEFF", participantID: bobLID)
		let keys = try CallMediaCrypto.deriveRTCPKeys(callKey: callKey, participantID: bobLID)
		let report = CallRTCP.senderReport(
			ssrc: bobSSRC,
			rtpTimestamp: 0,
			packetsSent: 0,
			octetsSent: 0,
			wallclockMs: 0,
			cname: [UInt8](repeating: 0x61, count: 18),
			report: CallRTCP.ReceptionReport(
				ssrc: ssrc,
				fractionLost: 64,
				cumulativeLost: 0,
				extendedHighestSequence: 0,
				jitter: 0,
				lastSenderReport: 0,
				delaySinceLastSenderReport: 0,
				bytesReceived: 0,
				receiveRateBps: 0
			)
		)
		await relay.receive(from: 1, try CallMediaCrypto.protectRTCP(report, keys: keys, senderSSRC: bobSSRC, index: 1))

		let value = await reader.value
		#expect(value == Int(Double(CallSession.initialVideoBitrate) * 0.8))
		await alice.stop()
		await bob.stop()
	}

	@Test("audio arriving inside video and FEC packets is played, and only once")
	func carriedAudio() async throws {
		let (alice, bob, relay) = try await legs()
		let reader = Task { () -> Int in
			var frames = 0
			for await _ in bob.receivedAudio {
				frames += 1
				break
			}
			return frames
		}

		// What a WhatsApp client's video encoder does with its queued audio.
		let ssrc = CallRelayAllocate.videoSSRC(callID: "00112233445566778899AABBCCDDEEFF", participantID: aliceLID)
		let keys = try CallMediaCrypto.deriveRTPKeys(callKey: callKey, participantID: aliceLID)
		let encoder = try CallOpusEncoder()
		let opus = try encoder.encode((0..<960).map { Int16(8_000 * sin(2 * .pi * 440 * Double($0) / 16_000)) })
		let audioPacket = CallRTPHeader(sequenceNumber: 1, timestamp: 960, ssrc: 0xaaaa).encoded() + opus
		let media = Data(slice(type: 1, size: 20))
		var header = CallRTPHeader(marker: true, payloadType: 97, sequenceNumber: 1, timestamp: 100, ssrc: ssrc).encoded()
		header[0] = 0x90
		header[15] = 1
		header += Data([0x71, UInt8(media.count >> 8), UInt8(media.count & 0xff), 0])
		var carrier = header
		carrier += try CallMediaCrypto.cryptPayload(media + audioPacket, keys: keys, ssrc: ssrc, roc: 0, sequence: 1)
		carrier += CallMediaCrypto.warpTag(authKey: keys.authKey, packetWithoutTag: carrier, roc: 0)
		await relay.receive(from: 0, carrier)

		let videoReader = first(bob.receivedVideo, count: 1)
		#expect(await reader.value == 1)
		#expect(await bob.carriedAudioPackets == 1)
		#expect(await videoReader.value.first?.data == annexB([[UInt8](media)]))

		await relay.receive(from: 0, carrier)
		try? await Task.sleep(for: .milliseconds(30))
		#expect(await bob.carriedAudioPackets == 1)
		await alice.stop()
		await bob.stop()
	}

	private func quietLegs(timeout: Duration) async throws -> (alice: CallSession, bob: CallSession) {
		let relay = VideoFakeRelay()
		func configuration(_ me: String, _ peer: String) -> CallSession.Configuration {
			CallSession.Configuration(
				callID: "00112233445566778899AABBCCDDEEFF",
				selfParticipantID: me,
				peerParticipantID: peer,
				callKey: callKey,
				relay: relayData
			)
		}
		let alice = try CallSession(
			configuration: configuration(aliceLID, bobLID),
			link: await VideoFakeLink(relay: relay, leg: 0),
			peerSilenceTimeout: timeout
		)
		let bob = try CallSession(
			configuration: configuration(bobLID, aliceLID),
			link: await VideoFakeLink(relay: relay, leg: 1),
			peerSilenceTimeout: timeout
		)
		try await alice.start()
		try await bob.start()
		return (alice, bob)
	}

	@Test("a peer that stops sending anything is reported gone, once")
	func peerGoesSilent() async throws {
		let (alice, bob) = try await quietLegs(timeout: .milliseconds(300))
		let reports = Task { () -> Int in
			var count = 0
			for await _ in bob.peerGone {
				count += 1
			}
			return count
		}

		await alice.setVideoSending(true)
		try await alice.sendVideo(annexB([sps, pps, slice(type: 5, size: 100)]), timestamp: 0)
		try await Task.sleep(for: .milliseconds(1_000))
		await bob.stop()

		#expect(await reports.value == 1)
		await alice.stop()
	}

	@Test("a peer still sending is not reported gone")
	func peerStaysActive() async throws {
		let (alice, bob) = try await quietLegs(timeout: .milliseconds(400))
		let reports = Task { () -> Int in
			var count = 0
			for await _ in bob.peerGone {
				count += 1
			}
			return count
		}

		await alice.setVideoSending(true)
		let delta = annexB([slice(type: 1, size: 100)])
		try await alice.sendVideo(annexB([sps, pps, slice(type: 5, size: 100)]), timestamp: 0)
		for index in 1...10 {
			try await Task.sleep(for: .milliseconds(100))
			try await alice.sendVideo(delta, timestamp: UInt32(index) * 4_500)
		}
		await bob.stop()

		#expect(await reports.value == 0)
		await alice.stop()
	}

	@Test("a call that never heard from the peer waits")
	func neverHeard() async throws {
		let (alice, bob) = try await quietLegs(timeout: .milliseconds(200))
		let reports = Task { () -> Int in
			var count = 0
			for await _ in alice.peerGone {
				count += 1
			}
			return count
		}

		try await Task.sleep(for: .milliseconds(600))
		await alice.stop()

		#expect(await reports.value == 0)
		await bob.stop()
	}

	@Test("voice calls still cross with a video plane beside them")
	func voiceUntouched() async throws {
		let (alice, bob, _) = try await legs()
		let reader = Task { () -> Int in
			var frames = 0
			for await _ in bob.receivedAudio {
				frames += 1
				break
			}
			return frames
		}
		for index in 0..<8 {
			try await alice.sendAudio((0..<960).map { Int16(8_000 * sin(2 * .pi * 440 * Double($0 + index * 960) / 16_000)) })
		}
		#expect(await reader.value == 1)
		#expect(await bob.videoPacketsRejected == 0)
		await alice.stop()
		await bob.stop()
	}
}

@Suite("Opus packets holding several frames")
struct CallOpusPacketTests {
	private func tone(_ offset: Int) -> [Int16] {
		(0..<960).map { Int16(9_000 * sin(2 * .pi * 300 * Double($0 + offset) / 16_000)) }
	}

	@Test("a one-frame packet passes through untouched")
	func codeZero() {
		let packet = Data([0x58, 1, 2, 3])
		#expect(CallOpusPacket.frames(in: packet) == [packet])
	}

	@Test("code 1 splits into two equal frames, and needs an even body")
	func codeOne() {
		#expect(CallOpusPacket.frames(in: Data([0x59, 1, 2, 3, 4])) == [Data([0x58, 1, 2]), Data([0x58, 3, 4])])
		#expect(CallOpusPacket.frames(in: Data([0x59, 1, 2, 3])) == nil)
	}

	@Test("code 2 reads the first frame's length, in one byte or two")
	func codeTwo() {
		#expect(CallOpusPacket.frames(in: Data([0x5a, 2, 1, 2, 3])) == [Data([0x58, 1, 2]), Data([0x58, 3])])

		let body = [UInt8](repeating: 7, count: 300)
		// 252 + 4 * 12 = 300.
		let long = CallOpusPacket.frames(in: Data([0x5a, 252, 12] + body + [9]))
		#expect(long == [Data([0x58] + body), Data([0x58, 9])])

		#expect(CallOpusPacket.frames(in: Data([0x5a, 200, 1, 2])) == nil)
		#expect(CallOpusPacket.frames(in: Data([0x5a])) == nil)
		#expect(CallOpusPacket.frames(in: Data([0x5a, 252])) == nil)
	}

	@Test("code 3 reads constant and variable frames, with padding")
	func codeThree() {
		// Constant: two frames of two bytes.
		#expect(CallOpusPacket.frames(in: Data([0x5b, 0x02, 1, 2, 3, 4])) == [Data([0x58, 1, 2]), Data([0x58, 3, 4])])
		// Variable: three frames, the last taking what remains.
		#expect(CallOpusPacket.frames(in: Data([0x5b, 0x83, 1, 2, 9, 8, 7, 6])) == [Data([0x58, 9]), Data([0x58, 8, 7]), Data([0x58, 6])])
		// Padding of two bytes behind one frame.
		#expect(CallOpusPacket.frames(in: Data([0x5b, 0x41, 2, 5, 6, 0, 0])) == [Data([0x58, 5, 6])])
		// Malformed: no frames, a body that does not divide, padding longer than the packet.
		#expect(CallOpusPacket.frames(in: Data([0x5b, 0x00])) == nil)
		#expect(CallOpusPacket.frames(in: Data([0x5b, 0x02, 1, 2, 3])) == nil)
		#expect(CallOpusPacket.frames(in: Data([0x5b, 0x41, 200, 5])) == nil)
	}

	@Test("a frame with no bytes has nothing to decode")
	func emptyFrame() {
		#expect(CallOpusPacket.frames(in: Data([0x5a, 0, 3])) == [Data([0x58, 3])])
		#expect(CallOpusPacket.frames(in: Data([0x59])) == [])
	}

	@Test("the decoder plays all 120 ms of the two-frame packet a phone sends in a video call")
	func decodesTwoFrames() throws {
		let encoder = try CallOpusEncoder()
		let decoder = try CallOpusDecoder()
		var frames = [Data]()
		for index in 0..<5 {
			frames.append(try encoder.encode(tone(index * 960)))
		}
		for frame in frames.prefix(3) {
			_ = try decoder.decode(frame)
		}

		let body = frames[3].dropFirst()
		var variable = Data([(frames[3][0] & 0xfc) | 0x02, UInt8(body.count)])
		variable.append(body)
		variable.append(frames[4].dropFirst())
		#expect(variable[0] == 0x5a)

		let samples = try decoder.decode(variable)
		#expect(samples.count == 1920)
		#expect((samples.map { abs(Int($0)) }.max() ?? 0) > 3_000)
	}
}

@Suite("Call video codec", .timeLimit(.minutes(1)))
struct CallVideoCodecTests {
	private func pixelBuffer(width: Int, height: Int, luma: UInt8) throws -> CVPixelBuffer {
		var buffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			width,
			height,
			kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
			[kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary,
			&buffer
		)
		let created = try #require(status == kCVReturnSuccess ? buffer : nil)
		CVPixelBufferLockBaseAddress(created, [])
		defer { CVPixelBufferUnlockBaseAddress(created, []) }
		for plane in 0..<2 {
			let base = CVPixelBufferGetBaseAddressOfPlane(created, plane)
			let rows = CVPixelBufferGetHeightOfPlane(created, plane)
			let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(created, plane)
			memset(base, plane == 0 ? Int32(luma) : 128, rows * rowBytes)
			if plane == 0, let base {
				// Some texture, so the encoder has more to say than a flat field.
				let bytes = base.assumingMemoryBound(to: UInt8.self)
				for row in stride(from: 0, to: rows, by: 7) {
					memset(bytes + row * rowBytes, Int32(row % 200 + 20), rowBytes)
				}
			}
		}
		return created
	}

	private final class Collector: @unchecked Sendable {
		private let lock = NSLock()
		private var frames = [CallEncodedVideoFrame]()
		private var decoded = [CVPixelBuffer]()

		func add(_ frame: CallEncodedVideoFrame) {
			lock.withLock { frames.append(frame) }
		}

		func add(_ buffer: CVPixelBuffer) {
			lock.withLock { decoded.append(buffer) }
		}

		var encoded: [CallEncodedVideoFrame] {
			lock.withLock { frames }
		}

		var pictures: [CVPixelBuffer] {
			lock.withLock { decoded }
		}
	}

	private func encodeFrames(count: Int, size: (Int, Int) = (640, 360)) async throws -> (CallVideoEncoder, Collector) {
		let collector = Collector()
		let encoder = try CallVideoEncoder(width: size.0, height: size.1, bitrate: 800_000) { collector.add($0) }
		for index in 0..<count {
			let buffer = try pixelBuffer(width: size.0, height: size.1, luma: UInt8(40 + index))
			encoder.encode(buffer, presentationTime: CMTime(value: CMTimeValue(index), timescale: 20))
			try await Task.sleep(for: .milliseconds(5))
		}
		for _ in 0..<200 where collector.encoded.count < count {
			try await Task.sleep(for: .milliseconds(10))
		}
		return (encoder, collector)
	}

	@Test("encodes Constrained Baseline in Annex-B, starting from an IDR with its parameter sets")
	func encodes() async throws {
		let (encoder, collector) = try await encodeFrames(count: 6)
		defer { encoder.invalidate() }

		let first = try #require(collector.encoded.first)
		#expect(first.isKeyframe)
		#expect(first.timestamp == 0)
		let types = CallH264.splitAnnexB(first.accessUnit).map(CallH264.nalType)
		#expect(types.prefix(2) == [CallH264.typeSPS, CallH264.typePPS])
		#expect(types.contains(CallH264.typeIDR))

		let sps = try #require(CallH264.splitAnnexB(first.accessUnit).first)
		#expect(sps[sps.startIndex + 1] == 66, "profile_idc is Baseline")
		#expect(sps[sps.startIndex + 2] & 0x40 != 0, "constraint_set1 makes it Constrained Baseline")

		let later = try #require(collector.encoded.last)
		#expect(later.timestamp == UInt32(collector.encoded.count - 1) * 4_500)
	}

	@Test("skips pictures past the call's frame rate")
	func throttles() async throws {
		let collector = Collector()
		let encoder = try CallVideoEncoder(width: 320, height: 180, bitrate: 300_000) { collector.add($0) }
		defer { encoder.invalidate() }
		for index in 0..<12 {
			let buffer = try pixelBuffer(width: 320, height: 180, luma: 60)
			// 60 fps from the camera, 20 on the wire.
			encoder.encode(buffer, presentationTime: CMTime(value: CMTimeValue(index), timescale: 60))
		}
		try await Task.sleep(for: .milliseconds(300))
		#expect(collector.encoded.count <= 5)
		#expect(collector.encoded.count >= 3)
	}

	@Test("a requested keyframe comes on the next picture")
	func requestedKeyframe() async throws {
		let collector = Collector()
		let encoder = try CallVideoEncoder(width: 320, height: 180, bitrate: 300_000) { collector.add($0) }
		defer { encoder.invalidate() }
		for index in 0..<6 {
			if index == 3 {
				encoder.requestKeyframe()
			}
			let buffer = try pixelBuffer(width: 320, height: 180, luma: UInt8(50 + index))
			encoder.encode(buffer, presentationTime: CMTime(value: CMTimeValue(index), timescale: 20))
			try await Task.sleep(for: .milliseconds(20))
		}
		for _ in 0..<100 where collector.encoded.count < 6 {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(collector.encoded.count == 6)
		#expect(collector.encoded[0].isKeyframe)
		#expect(!collector.encoded[1].isKeyframe)
		#expect(collector.encoded[3].isKeyframe)
	}

	@Test("the decoder rebuilds the encoder's pictures through RTP packetization")
	func decodesThroughRTP() async throws {
		let (encoder, collector) = try await encodeFrames(count: 10)
		defer { encoder.invalidate() }
		let output = Collector()
		let decoder = CallVideoDecoder { output.add($0) }
		defer { decoder.invalidate() }

		var depacketizer = CallH264Depacketizer()
		var sequence: UInt16 = 0
		for frame in collector.encoded {
			let payloads = CallH264.packetize(frame.accessUnit)
			for (index, payload) in payloads.enumerated() {
				let units = depacketizer.push(
					sequence: sequence,
					timestamp: frame.timestamp,
					payload: payload,
					marker: index == payloads.count - 1
				)
				sequence &+= 1
				for unit in units {
					#expect(decoder.decode(unit.data) == .decoded)
				}
			}
		}

		#expect(output.pictures.count == collector.encoded.count)
		let picture = try #require(output.pictures.last)
		#expect(CVPixelBufferGetWidth(picture) == 640)
		#expect(CVPixelBufferGetHeight(picture) == 360)
	}

	@Test("a decoder with no parameter sets asks for a keyframe, then recovers on one")
	func decoderWaitsForKeyframe() async throws {
		let (encoder, collector) = try await encodeFrames(count: 4)
		defer { encoder.invalidate() }
		let output = Collector()
		let decoder = CallVideoDecoder { output.add($0) }
		defer { decoder.invalidate() }

		#expect(decoder.decode(collector.encoded[1].accessUnit) == .needsKeyframe)
		#expect(output.pictures.isEmpty)
		#expect(decoder.decode(collector.encoded[0].accessUnit) == .decoded)
		#expect(decoder.decode(collector.encoded[1].accessUnit) == .decoded)
		#expect(output.pictures.count == 2)
	}
}
