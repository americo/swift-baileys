import Foundation

/// One picture from one participant of a group call.
public struct CallParticipantVideoFrame: Equatable, Sendable {
	/// The device's id in the call's keys, which is how the rest of the app tells streams apart.
	public let participantID: String
	public let frame: CallVideoFrame

	public init(participantID: String, frame: CallVideoFrame) {
		self.participantID = participantID
		self.frame = frame
	}
}

public enum CallGroupMediaError: Error, Equatable, Sendable {
	case invalidSnapshot
	case invalidEpoch
	case conflictingEpoch
	case identityMismatch
	/// The roster no longer holds this device, which ends the call for it.
	case localParticipantRemoved
	case tagLengthChanged
}

/// Participant-indexed receive state of a group call.
///
/// Packets are routed by deterministic SSRC before they are authenticated, and a shared key is then
/// derived with that sender's own device id, so keys are never tried across participants. A key
/// (epoch) and the roster it belongs to can arrive in either order: one for a transaction the roster has
/// not reached waits here, within a bound, until it does.
struct CallGroupMediaRegistry {
	enum RosterApply: Equatable {
		case applied
		case stale
	}

	enum EpochApply: Equatable {
		case installed
		case buffered
		case stale
		case duplicate
	}

	struct Receiver {
		let participantID: String
		var userJID: String
		var deviceJID: String
		var pid: UInt32?
		let audioSSRC: UInt32
		let videoSSRC: UInt32
		let appDataSSRC: UInt32
		var isVideoEnabled: Bool
		var audio: CallAudioPipeline?
		var video: CallVideoPipeline?
		var appData: CallAudioPipeline?
		var rtcpKeys: CallSRTPKeys?
	}

	static let maxBufferedEpochs = 8

	let callID: String
	let callCreator: String
	let localDevice: String
	private let localParticipantID: String
	private let tagLength: Int

	private(set) var rosterTransaction: UInt32?
	private(set) var installedEpoch: GroupCallEpoch?
	private var pendingEpochs = [UInt32: Data]()
	private(set) var receivers = [String: Receiver]()
	private var audioRoutes = [UInt32: String]()
	private var videoRoutes = [UInt32: String]()
	private var appDataRoutes = [UInt32: String]()
	/// Every stream slot of each participant, for its RTCP and its auxiliary streams.
	private var slotRoutes = [UInt32: String]()

	init(callID: String, callCreator: String, localDevice: String, tagLength: Int) {
		self.callID = callID
		self.callCreator = callCreator
		self.localDevice = localDevice
		self.localParticipantID = CallMediaCrypto.formatParticipantID(localDevice)
		self.tagLength = tagLength
	}

	// MARK: Reading

	/// Participants media can currently be received from.
	var activeParticipantIDs: Set<String> {
		Set(receivers.values.filter { $0.audio != nil }.map(\.participantID))
	}

	var activePIDs: [UInt32] {
		Array(Set(receivers.values.compactMap(\.pid))).sorted()
	}

	var activeDeviceIDs: Set<String> {
		Set(receivers.keys)
	}

	func participantID(forAudio ssrc: UInt32) -> String? {
		audioRoutes[ssrc]
	}

	func participantID(forVideo ssrc: UInt32) -> String? {
		videoRoutes[ssrc]
	}

	func participantID(forAppData ssrc: UInt32) -> String? {
		appDataRoutes[ssrc]
	}

	func participantID(forSlot ssrc: UInt32) -> String? {
		slotRoutes[ssrc]
	}

	/// Devices whose relay session this update replaces.
	func participantsWithPIDChanges(_ update: GroupCallUpdate) -> [String] {
		update.activeRemoteDevices(localDevice: localDevice).compactMap { _, device in
			let id = CallMediaCrypto.formatParticipantID(device.jid)
			return receivers[id].flatMap { Self.pidMigrated($0.pid, device.pid) ? id : nil }
		}
	}

	// MARK: Receiving

	mutating func unprotectAudio(_ packet: Data, from participantID: String) throws -> CallAudioPipeline.Received? {
		try receivers[participantID]?.audio?.unprotect(packet)
	}

	mutating func acceptCarriedAudio(_ packet: Data, from participantID: String) -> CallAudioPipeline.Received? {
		receivers[participantID]?.audio?.acceptCarried(packet)
	}

	mutating func unprotectVideo(_ packet: Data, from participantID: String) throws -> CallVideoPipeline.Received? {
		guard receivers[participantID]?.isVideoEnabled == true else {
			return nil
		}

		return try receivers[participantID]?.video?.unprotect(packet)
	}

	mutating func unprotectAuxiliary(_ packet: Data, from participantID: String) throws -> Data? {
		try receivers[participantID]?.video?.unprotectAuxiliary(packet)
	}

	mutating func unprotectAppData(_ packet: Data, from participantID: String) throws -> CallAudioPipeline.Received? {
		try receivers[participantID]?.appData?.unprotect(packet)
	}

	func rtcpKeys(for participantID: String) -> CallSRTPKeys? {
		receivers[participantID]?.rtcpKeys
	}

	// MARK: Updating

	/// Seeds the peer of a 1:1 call being promoted, so it stays heard until a roster and a key replace it.
	mutating func seedDirectPeer(callKey: Data, userJID: String, deviceJID: String, video: Bool) throws {
		let receiver = try makeReceiver(key: callKey, userJID: userJID, deviceJID: deviceJID, pid: nil, video: video)
		receivers[receiver.participantID] = receiver
		try rebuildRoutes()
	}

	/// Replaces the roster. A device that stays keeps its receiver, so its rollover state and what it has
	/// half reassembled survive the update.
	mutating func apply(_ update: GroupCallUpdate) throws -> RosterApply {
		guard update.callID == callID, update.callCreator == callCreator else {
			throw CallGroupMediaError.identityMismatch
		}
		guard GroupCallState.isValid(update, isPartial: true) else {
			throw CallGroupMediaError.invalidSnapshot
		}
		if let rosterTransaction, update.transactionID <= rosterTransaction {
			return .stale
		}

		let isVideo = update.isVideo
		let active = update.activeRemoteDevices(localDevice: localDevice)
		let epochKey = installedEpoch?.key
		var previous = receivers
		var next = [String: Receiver]()
		for (participant, device) in active {
			let id = CallMediaCrypto.formatParticipantID(device.jid)
			var receiver: Receiver
			if let existing = previous.removeValue(forKey: id) {
				if Self.pidMigrated(existing.pid, device.pid) {
					// A PID is one relay media session, and its replacement starts its own sequence.
					receiver = try epochKey.map {
						try makeReceiver(key: $0, userJID: participant.jid, deviceJID: device.jid, pid: device.pid, video: isVideo)
					} ?? keylessReceiver(userJID: participant.jid, deviceJID: device.jid, pid: device.pid)
				} else if isVideo, existing.video == nil, let epochKey {
					receiver = try makeReceiver(key: epochKey, userJID: participant.jid, deviceJID: device.jid, pid: device.pid, video: true)
					receiver.audio = existing.audio
					receiver.appData = existing.appData
				} else {
					receiver = existing
				}
			} else if let epochKey {
				receiver = try makeReceiver(key: epochKey, userJID: participant.jid, deviceJID: device.jid, pid: device.pid, video: isVideo)
			} else {
				receiver = keylessReceiver(userJID: participant.jid, deviceJID: device.jid, pid: device.pid)
			}

			receiver.userJID = participant.jid
			receiver.deviceJID = device.jid
			receiver.pid = device.pid
			if !isVideo, receiver.isVideoEnabled {
				// Half a picture from before the downgrade must not complete under the new roster.
				receiver.video?.resetReassembly()
			}
			receiver.isVideoEnabled = isVideo
			next[id] = receiver
		}

		receivers = next
		rosterTransaction = update.transactionID
		try installBestPendingEpoch()
		try rebuildRoutes()
		return .applied
	}

	mutating func applyEpoch(transactionID: UInt32, key: Data) throws -> EpochApply {
		guard transactionID != 0, key.count == CallMediaCrypto.callKeyLength else {
			throw CallGroupMediaError.invalidEpoch
		}
		if let installedEpoch {
			if transactionID < installedEpoch.transactionID {
				return .stale
			}
			if transactionID == installedEpoch.transactionID {
				guard installedEpoch.key == key else {
					throw CallGroupMediaError.conflictingEpoch
				}

				return .duplicate
			}
		}
		if let pending = pendingEpochs[transactionID] {
			guard pending == key else {
				throw CallGroupMediaError.conflictingEpoch
			}

			return .duplicate
		}

		if rosterTransaction.map({ transactionID > $0 }) ?? true {
			pendingEpochs[transactionID] = key
			// A legitimate next key displaces the farthest speculative one.
			if pendingEpochs.count > Self.maxBufferedEpochs, let farthest = pendingEpochs.keys.max() {
				pendingEpochs.removeValue(forKey: farthest)
			}
			return .buffered
		}

		try install(GroupCallEpoch(transactionID: transactionID, key: key))
		return .installed
	}

	private mutating func installBestPendingEpoch() throws {
		guard let rosterTransaction,
			  let best = pendingEpochs.keys.filter({ $0 <= rosterTransaction }).max(),
			  let key = pendingEpochs.removeValue(forKey: best) else {
			return
		}

		try install(GroupCallEpoch(transactionID: best, key: key))
		pendingEpochs = pendingEpochs.filter { $0.key > best }
	}

	private mutating func install(_ epoch: GroupCallEpoch) throws {
		var next = receivers
		for (id, receiver) in receivers {
			guard var audio = receiver.audio else {
				next[id] = try makeReceiver(
					key: epoch.key,
					userJID: receiver.userJID,
					deviceJID: receiver.deviceJID,
					pid: receiver.pid,
					video: receiver.isVideoEnabled
				)
				continue
			}

			var updated = receiver
			try audio.rekeyReceive(callKey: epoch.key, peerParticipantID: receiver.participantID)
			updated.audio = audio
			try updated.video?.rekeyReceive(callKey: epoch.key, peerParticipantID: receiver.participantID)
			try updated.appData?.rekeyReceive(callKey: epoch.key, peerParticipantID: receiver.participantID)
			updated.rtcpKeys = try CallMediaCrypto.deriveRTCPKeys(callKey: epoch.key, participantID: receiver.participantID)
			next[id] = updated
		}

		receivers = next
		installedEpoch = epoch
		try rebuildRoutes()
	}

	private func makeReceiver(key: Data, userJID: String, deviceJID: String, pid: UInt32?, video: Bool) throws -> Receiver {
		let id = CallMediaCrypto.formatParticipantID(deviceJID)
		let audioSSRC = CallRelayAllocate.audioSSRC(callID: callID, participantID: id)
		let videoSSRC = CallRelayAllocate.videoSSRC(callID: callID, participantID: id)
		let appDataSSRC = CallRelayAllocate.ssrc(callID: callID, participantID: id, slot: CallRelayAllocate.appDataSlot)
		return try Receiver(
			participantID: id,
			userJID: userJID,
			deviceJID: deviceJID,
			pid: pid,
			audioSSRC: audioSSRC,
			videoSSRC: videoSSRC,
			appDataSSRC: appDataSSRC,
			isVideoEnabled: video,
			audio: CallAudioPipeline(
				callKey: key,
				selfParticipantID: localParticipantID,
				peerParticipantID: id,
				ssrc: audioSSRC,
				tagLength: tagLength
			),
			video: video ? CallVideoPipeline(
				callKey: key,
				selfParticipantID: localParticipantID,
				peerParticipantID: id,
				ssrc: videoSSRC,
				tagLength: tagLength
			) : nil,
			appData: CallAudioPipeline(
				callKey: key,
				selfParticipantID: localParticipantID,
				peerParticipantID: id,
				ssrc: appDataSSRC,
				tagLength: tagLength,
				payloadType: CallAppData.payloadType,
				samplesPerPacket: CallAppData.timestampStride
			),
			rtcpKeys: CallMediaCrypto.deriveRTCPKeys(callKey: key, participantID: id)
		)
	}

	private func keylessReceiver(userJID: String, deviceJID: String, pid: UInt32?) -> Receiver {
		let id = CallMediaCrypto.formatParticipantID(deviceJID)
		return Receiver(
			participantID: id,
			userJID: userJID,
			deviceJID: deviceJID,
			pid: pid,
			audioSSRC: CallRelayAllocate.audioSSRC(callID: callID, participantID: id),
			videoSSRC: CallRelayAllocate.videoSSRC(callID: callID, participantID: id),
			appDataSSRC: CallRelayAllocate.ssrc(callID: callID, participantID: id, slot: CallRelayAllocate.appDataSlot),
			isVideoEnabled: false,
			audio: nil,
			video: nil,
			appData: nil,
			rtcpKeys: nil
		)
	}

	private mutating func rebuildRoutes() throws {
		var audio = [UInt32: String]()
		var video = [UInt32: String]()
		var appData = [UInt32: String]()
		var slots = [UInt32: String]()
		for receiver in receivers.values where receiver.audio != nil {
			guard audio.updateValue(receiver.participantID, forKey: receiver.audioSSRC) == nil else {
				throw CallGroupMediaError.invalidSnapshot
			}
			if receiver.isVideoEnabled, receiver.video != nil,
			   video.updateValue(receiver.participantID, forKey: receiver.videoSSRC) != nil {
				throw CallGroupMediaError.invalidSnapshot
			}
			if receiver.appData != nil {
				appData[receiver.appDataSSRC] = receiver.participantID
			}
			for slot in UInt32(0)..<UInt32(CallRelayAllocate.streamSlots.count) {
				let ssrc = CallRelayAllocate.ssrc(callID: callID, participantID: receiver.participantID, slot: slot)
				guard slots.updateValue(receiver.participantID, forKey: ssrc) == nil else {
					throw CallGroupMediaError.invalidSnapshot
				}
			}
		}

		audioRoutes = audio
		videoRoutes = video
		appDataRoutes = appData
		slotRoutes = slots
	}

	/// A seeded peer has no PID yet, so adopting its first one is not a new session.
	static func pidMigrated(_ existing: UInt32?, _ incoming: UInt32?) -> Bool {
		existing != nil && existing != incoming
	}
}

/// Mixes the participants of a group call into one playout: independent bounded queues, summed in fixed
/// 10 ms chunks with saturation.
struct CallGroupAudioMixer {
	/// 10 ms at 16 kHz.
	static let chunkSamples = 160
	/// Two 60 ms packets wait before a participant joins playout, as a floor for longer packets.
	static let prefillSamples = 1920
	/// Four 60 ms packets. Overflow drops the oldest samples, to keep to real time.
	static let capacitySamples = 3840
	/// A participant who spoke briefly and went quiet must not wait for later speech: about 200 ms.
	static let maxPrimeChunks = 20

	private struct Queue {
		var samples = [Int16]()
		var isPrimed = false
		var primingChunks = 0
		/// The largest packet delivered. A stream sending longer packets needs a longer cushion.
		var packetSamples = 0

		var prefill: Int { max(packetSamples * 2, CallGroupAudioMixer.prefillSamples) }
		var capacity: Int { max(packetSamples * 4, CallGroupAudioMixer.capacitySamples) }
	}

	private var allowed: Set<String>?
	private var queues = [String: Queue]()

	/// Gates later audio to the roster, and drops the queues of those who left.
	mutating func retain(_ participants: Set<String>) {
		queues = queues.filter { participants.contains($0.key) }
		allowed = participants
	}

	/// Drops what is queued for a participant whose media session was replaced.
	mutating func reset(_ participant: String) {
		queues.removeValue(forKey: participant)
	}

	/// Queues one decoded packet. False for someone not on the roster.
	@discardableResult
	mutating func push(_ participant: String, _ samples: [Int16]) -> Bool {
		guard !samples.isEmpty, allowed.map({ $0.contains(participant) }) ?? true else {
			return false
		}

		var queue = queues[participant] ?? Queue()
		queue.packetSamples = max(queue.packetSamples, samples.count)
		queue.samples += samples
		if queue.samples.count > queue.capacity {
			queue.samples.removeFirst(queue.samples.count - queue.capacity)
		}
		if queue.samples.count >= queue.prefill {
			queue.isPrimed = true
			queue.primingChunks = 0
		}
		queues[participant] = queue
		return true
	}

	/// Mixes one chunk, or nil when nobody is ready to be heard.
	mutating func mixChunk() -> [Int16]? {
		var mixed: [Int32]?
		for (participant, var queue) in queues {
			if !queue.isPrimed {
				if queue.samples.isEmpty {
					queue.primingChunks = 0
				} else {
					queue.primingChunks += 1
					if queue.primingChunks >= Self.maxPrimeChunks {
						queue.isPrimed = true
						queue.primingChunks = 0
					}
				}
			}
			if queue.isPrimed, !queue.samples.isEmpty {
				var sum = mixed ?? [Int32](repeating: 0, count: Self.chunkSamples)
				let taken = min(Self.chunkSamples, queue.samples.count)
				for index in 0..<taken {
					sum[index] += Int32(queue.samples[index])
				}
				mixed = sum
				queue.samples.removeFirst(taken)
				if queue.samples.isEmpty {
					queue.isPrimed = false
					queue.primingChunks = 0
				}
			}
			queues[participant] = queue
		}

		return mixed?.map { Int16(clamping: $0) }
	}
}
