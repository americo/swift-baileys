import Foundation

/// H.264 byte stream handling for the video half of a call: NAL splitting and RFC 6184
/// packetization. Nothing here touches pixels; `CallVideoEncoder` and `CallVideoDecoder` do that.
public enum CallH264 {
	/// Largest RTP payload sent before a NAL is fragmented. WhatsApp's own senders fill FU-A payloads
	/// to this size. With the 28-byte video header and a tag of at most 20 bytes, a packet stays
	/// inside one SCTP chunk of the relay association.
	public static let singleNALMax = 960
	/// Reassembly cap: a NAL or access unit past this is garbage, not video.
	public static let maxAccessUnitBytes = 4 * 1024 * 1024

	static let fragmentMax = singleNALMax - 2
	static let typeIDR: UInt8 = 5
	static let typeSEI: UInt8 = 6
	static let typeSPS: UInt8 = 7
	static let typePPS: UInt8 = 8
	static let typeAUD: UInt8 = 9
	static let typeSTAPA: UInt8 = 24
	static let typeFUA: UInt8 = 28

	static let startCode: [UInt8] = [0, 0, 0, 1]

	/// The NAL units of an Annex-B buffer, without start codes.
	public static func splitAnnexB(_ data: Data) -> [Data] {
		let bytes = [UInt8](data)
		var units = [Data]()
		var nalStart: Int?
		var index = 0
		while index + 3 <= bytes.count {
			guard bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 else {
				index += 1
				continue
			}

			if let start = nalStart {
				let end = index > start && bytes[index - 1] == 0 ? index - 1 : index
				if end > start {
					units.append(Data(bytes[start..<end]))
				}
			}
			nalStart = index + 3
			index += 3
		}
		if let start = nalStart, start < bytes.count {
			units.append(Data(bytes[start...]))
		}

		return units
	}

	public static func nalType(_ nal: Data) -> UInt8 {
		(nal.first ?? 0) & 0x1f
	}

	/// Whether the access unit carries an IDR slice: a point a decoder can restart from.
	public static func hasIDR(_ accessUnit: Data) -> Bool {
		splitAnnexB(accessUnit).contains { nalType($0) == typeIDR }
	}

	/// RTP payloads for one Annex-B access unit: a single NAL when it fits, FU-A fragments when it
	/// does not, and small parameter sets aggregated into STAP-A. Access unit delimiters are dropped,
	/// and so is SEI ahead of the first slice, which decoders do not need.
	public static func packetize(_ accessUnit: Data) -> [Data] {
		var payloads = [Data]()
		var seenSlice = false
		var aggregate: (bytes: [UInt8], forbidden: UInt8, priority: UInt8)?

		func flushAggregate() {
			guard let open = aggregate else {
				return
			}

			var bytes = open.bytes
			bytes[0] = open.forbidden | open.priority | typeSTAPA
			payloads.append(Data(bytes))
			aggregate = nil
		}

		for nal in splitAnnexB(accessUnit) {
			let type = nalType(nal)
			if type == typeAUD || (!seenSlice && type == typeSEI) {
				continue
			}

			if (1...5).contains(type) {
				flushAggregate()
				seenSlice = true
				if nal.count <= singleNALMax {
					payloads.append(nal)
				} else {
					payloads += fragment(nal)
				}
				continue
			}

			let cost = 2 + nal.count
			let fits = aggregate.map { $0.bytes.count + cost <= singleNALMax } ?? (cost < singleNALMax)
			if !fits {
				flushAggregate()
				if cost >= singleNALMax {
					if nal.count <= singleNALMax {
						payloads.append(nal)
					} else {
						payloads += fragment(nal)
					}
					continue
				}
			}

			let header = nal[nal.startIndex]
			var open = aggregate ?? (bytes: [0], forbidden: header & 0x80, priority: header & 0x60)
			open.forbidden |= header & 0x80
			open.priority = max(open.priority, header & 0x60)
			open.bytes += [UInt8(nal.count >> 8), UInt8(nal.count & 0xff)]
			open.bytes += nal
			aggregate = open
		}
		flushAggregate()

		return payloads
	}

	/// One oversized NAL as an FU-A run, split evenly as WhatsApp's senders do: filling each fragment
	/// to the limit would leave a short tail that costs a packet and carries little.
	static func fragment(_ nal: Data) -> [Data] {
		let bytes = [UInt8](nal)
		let indicator = (bytes[0] & 0xe0) | typeFUA
		let type = bytes[0] & 0x1f
		let body = bytes[1...]
		let count = (body.count + fragmentMax - 1) / fragmentMax
		let base = body.count / count
		let longer = body.count % count

		var fragments = [Data]()
		fragments.reserveCapacity(count)
		var cursor = body.startIndex
		for index in 0..<count {
			let size = base + (index < longer ? 1 : 0)
			var header = type
			if index == 0 { header |= 0x80 }
			if index == count - 1 { header |= 0x40 }
			fragments.append(Data([indicator, header] + body[cursor..<(cursor + size)]))
			cursor += size
		}

		return fragments
	}
}

/// Rebuilds Annex-B access units from RTP payloads.
///
/// An access unit completes on its marker packet, or when a later timestamp shows the marker was
/// lost, so two pictures never merge. A lost fragment drops its NAL rather than hand the decoder a
/// truncated slice, and malformed input only ever costs NALs.
public struct CallH264Depacketizer {
	public struct AccessUnit: Equatable, Sendable {
		public let timestamp: UInt32
		public let data: Data
	}

	/// Largest change in a sender's media time offset still read as the same picture on one RTP
	/// timestamp. One picture's packets differ by about 1 ms, and a picture an iPhone sends on its
	/// predecessor's timestamp by a whole frame interval (about 67 ms at 15 fps).
	static let samePictureOffsetMs = 8
	static let ticksPerMs = 90
	static let maxReady = 4

	private struct Picture {
		var timestamp: UInt32
		var offset: Int16?
		var baseOffset: Int16?
		var lastSequence: UInt16

		init(timestamp: UInt32, offset: Int16?, sequence: UInt16) {
			self.timestamp = timestamp
			self.offset = offset
			self.baseOffset = offset
			self.lastSequence = sequence
		}

		var outputTimestamp: UInt32 {
			guard let offset, let baseOffset else {
				return timestamp
			}

			return timestamp &+ UInt32(truncatingIfNeeded: (Int32(offset) - Int32(baseOffset)) * Int32(ticksPerMs))
		}

		enum Order {
			case same, later, laterShared, earlier
		}

		func order(timestamp other: UInt32, offset otherOffset: Int16?) -> Order {
			if other != timestamp {
				return Int32(bitPattern: other &- timestamp) > 0 ? .later : .earlier
			}
			guard let offset, let otherOffset else {
				return .same
			}

			let delta = Int(otherOffset) - Int(offset)
			if abs(delta) <= samePictureOffsetMs {
				return .same
			}
			return delta > 0 ? .laterShared : .earlier
		}
	}

	private var unit = [UInt8]()
	private var fragment = [UInt8]()
	private var fragmentActive = false
	private var nextFragmentSequence: UInt16 = 0
	private var current: Picture?
	private var lastCompleted: Picture?
	private var ready = [AccessUnit]()

	/// Output timestamp of the picture the last packet joined; `nil` when it was discarded.
	public private(set) var lastPacketTimestamp: UInt32?

	public init() {}

	public mutating func reset() {
		unit.removeAll(keepingCapacity: true)
		fragment.removeAll(keepingCapacity: true)
		fragmentActive = false
		current = nil
		lastCompleted = nil
		lastPacketTimestamp = nil
		ready.removeAll()
	}

	/// Feeds one RTP payload and returns the access units it completed. `offsetMs` is the sender's
	/// media time offset, which tells apart two pictures sharing an RTP timestamp.
	public mutating func push(
		sequence: UInt16,
		timestamp: UInt32,
		offsetMs: Int16? = nil,
		payload: Data,
		marker: Bool
	) -> [AccessUnit] {
		lastPacketTimestamp = nil
		guard admit(sequence: sequence, timestamp: timestamp, offsetMs: offsetMs) else {
			return drainReady()
		}

		lastPacketTimestamp = current?.outputTimestamp
		let bytes = [UInt8](payload)
		if let first = bytes.first {
			appendPayload(bytes, type: first & 0x1f, sequence: sequence)
		}

		if marker, !unit.isEmpty {
			dropPartialFragment()
			let completed = current ?? Picture(timestamp: timestamp, offset: offsetMs, sequence: sequence)
			current = nil
			lastCompleted = completed
			finishUnit(at: completed.outputTimestamp)
		}

		return drainReady()
	}

	/// Places the packet in a picture. `false` means it belongs to one already past.
	private mutating func admit(sequence: UInt16, timestamp: UInt32, offsetMs: Int16?) -> Bool {
		func isAfter(_ last: UInt16) -> Bool {
			Int16(bitPattern: sequence &- last) > 0
		}

		if var picture = current {
			let order = picture.order(timestamp: timestamp, offset: offsetMs)
			switch order {
			case .same:
				if isAfter(picture.lastSequence) {
					picture.lastSequence = sequence
					current = picture
				}
				return true
			case .later, .laterShared:
				guard order == .later || isAfter(picture.lastSequence) else {
					return false
				}

				var next = Picture(timestamp: timestamp, offset: offsetMs, sequence: sequence)
				if order == .laterShared {
					next = picture
					next.offset = offsetMs
					next.lastSequence = sequence
				}
				// A new picture invalidates any partial NAL. Its predecessor goes out even without its
				// marker, since two pictures must not merge.
				dropPartialFragment()
				if !unit.isEmpty {
					finishUnit(at: picture.outputTimestamp)
				}
				lastCompleted = picture
				current = next
				return true
			case .earlier:
				return false
			}
		}

		guard let completed = lastCompleted else {
			current = Picture(timestamp: timestamp, offset: offsetMs, sequence: sequence)
			return true
		}

		switch completed.order(timestamp: timestamp, offset: offsetMs) {
		case .later:
			current = Picture(timestamp: timestamp, offset: offsetMs, sequence: sequence)
			return true
		case .laterShared where isAfter(completed.lastSequence):
			var next = completed
			next.offset = offsetMs
			next.lastSequence = sequence
			current = next
			return true
		default:
			return false
		}
	}

	private mutating func appendPayload(_ bytes: [UInt8], type: UInt8, sequence: UInt16) {
		switch type {
		case CallH264.typeSTAPA:
			dropPartialFragment()
			var cursor = 1
			while cursor + 2 <= bytes.count {
				let length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
				cursor += 2
				guard length > 0, cursor + length <= bytes.count else {
					return
				}

				appendNAL(bytes[cursor..<(cursor + length)])
				cursor += length
			}
		case CallH264.typeFUA:
			guard bytes.count >= 2 else {
				return
			}

			let header = bytes[1]
			if header & 0x80 != 0 {
				dropPartialFragment()
				fragmentActive = true
				fragment.append((bytes[0] & 0xe0) | (header & 0x1f))
			} else if fragmentActive, sequence != nextFragmentSequence {
				dropPartialFragment()
			}
			guard fragmentActive else {
				return
			}

			nextFragmentSequence = sequence &+ 1
			guard fragment.count + bytes.count <= CallH264.maxAccessUnitBytes else {
				dropPartialFragment()
				return
			}

			fragment += bytes[2...]
			if header & 0x40 != 0 {
				appendNAL(fragment[...])
				dropPartialFragment()
			}
		case 1...23:
			dropPartialFragment()
			appendNAL(bytes[...])
		default:
			break
		}
	}

	private mutating func appendNAL(_ nal: ArraySlice<UInt8>) {
		guard !nal.isEmpty, unit.count + CallH264.startCode.count + nal.count <= CallH264.maxAccessUnitBytes else {
			return
		}

		unit += CallH264.startCode
		unit += nal
	}

	private mutating func dropPartialFragment() {
		fragment.removeAll(keepingCapacity: true)
		fragmentActive = false
	}

	private mutating func finishUnit(at timestamp: UInt32) {
		if ready.count >= Self.maxReady {
			ready.removeFirst()
		}
		ready.append(AccessUnit(timestamp: timestamp, data: Data(unit)))
		unit.removeAll(keepingCapacity: true)
	}

	private mutating func drainReady() -> [AccessUnit] {
		defer { ready.removeAll() }
		return ready
	}
}
