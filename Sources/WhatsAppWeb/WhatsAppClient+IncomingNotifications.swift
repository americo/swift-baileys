import Foundation

extension WhatsAppClient {
	func handleNotificationNode(_ node: BinaryNode) async -> Bool {
		guard node.tag == "notification" else {
			return false
		}
		if let from = node.attrs["from"],
		   from != "@s.whatsapp.net",
		   configuration.shouldIgnoreJID(from) == true {
			if let ack = StanzaAck.build(for: node) {
				try? await sendNode(ack)
			}
			return true
		}

		if node.attrs["type"] == "picture" {
			handlePictureNotification(node)
			if let ack = StanzaAck.build(for: node) {
				try? await sendNode(ack)
			}

			return true
		}

		if node.attrs["type"] == "account_sync" {
			await handleAccountSyncNotification(node)
		}

		if node.attrs["type"] == "w:gp2" {
			handleGroupNotification(node)
		}

		if node.attrs["type"] == "devices" {
			handleDevicesNotification(node)
		}

		if node.attrs["type"] == "encrypt" {
			await handleEncryptNotification(node)
		}

		if node.attrs["type"] == "newsletter" {
			handleNewsletterNotification(node)
		}

		if node.attrs["type"] == "mex" {
			handleMexNotification(node)
		}

		if node.attrs["type"] == "link_code_companion_reg" {
			await handleLinkCodeCompanionRegistrationNotification(node)
		}

		if node.attrs["type"] == "privacy_token" {
			await handlePrivacyTokenNotification(node)
		}

		if node.attrs["type"] == "mediaretry" {
			if let update = mediaRetryUpdate(from: node) {
				eventContinuation.yield(.messageMediaUpdated([update]))
				await mediaUpdateCoordinator.receive(update)
			}
		}

		if node.attrs["type"] == "server_sync" {
			let collections = node.children(named: "collection").compactMap { $0.attrs["name"] }
			if !collections.isEmpty {
				eventContinuation.yield(.appStateSyncRequested(AppStateSyncRequest(collections: collections)))
				startAppStateSync(for: collections)
			}
		}

		if let ack = StanzaAck.build(for: node) {
			try? await sendNode(ack)
		}

		return true
	}

	private func startAppStateSync(for collections: [String]) {
		let knownCollections = collections.compactMap(AppStateCollectionName.init(rawValue:))
		guard authenticationState != nil, !knownCollections.isEmpty else {
			return
		}

		Task {
			try? await syncAppState(collections: knownCollections)
		}
	}

	private func handlePictureNotification(_ node: BinaryNode) {
		let setPicture = node.firstChild(named: "set")
		let deletePicture = node.firstChild(named: "delete")
		let id = node.attrs["from"].flatMap { JID($0)?.normalizedUser } ?? node.attrs["from"] ??
			setPicture?.attrs["hash"] ?? deletePicture?.attrs["hash"] ?? ""
		let imageURL = setPicture != nil ? "changed" : "removed"
		eventContinuation.yield(.contactsUpdated([ContactUpdate(id: id, imageURL: imageURL)]))

		guard JID(node.attrs["from"])?.server == JIDServer.group.rawValue else {
			return
		}

		let actor = setPicture?.attrs["author"] ?? deletePicture?.attrs["author"]
		let parameters = setPicture?.attrs["id"].map { [$0] } ?? []
		let stub = ReceivedMessageStubContent(type: .groupChangeIcon, parameters: parameters)
		eventContinuation.yield(.receivedMessage(ReceivedMessage(
			id: node.attrs["id"] ?? "",
			from: node.attrs["from"],
			timestamp: node.attrs["t"].flatMap(UInt64.init),
			content: .stub(stub),
			fromMe: JID.areSameUser(actor, authenticationState?.credentials.me?.id),
			participant: actor,
			keyParticipant: actor,
			stub: stub
		)))
	}

	private func handleAccountSyncNotification(_ node: BinaryNode) async {
		if let disappearingMode = node.firstChild(named: "disappearing_mode"),
		   let duration = disappearingMode.attrs["duration"].flatMap(Int.init),
		   let timestamp = disappearingMode.attrs["t"].flatMap(Int.init) {
			try? await updateCredentials { credentials in
				credentials.accountSettings.defaultDisappearingMode = AccountDisappearingModeSetting(
					ephemeralExpiration: duration,
					ephemeralSettingTimestamp: timestamp
				)
			}
		}

		if let blocklist = node.firstChild(named: "blocklist") {
			for item in blocklist.children(named: "item") {
				if let jid = item.attrs["jid"] {
					let updateType: BlocklistUpdateType = item.attrs["action"] == "block" ? .add : .remove
					eventContinuation.yield(.blocklistUpdated(BlocklistUpdate(jids: [jid], type: updateType)))
				}
			}
		}
	}

	private func handleGroupNotification(_ node: BinaryNode) {
		guard case let .nodes(children) = node.content,
			  let child = children.first,
			  let content = groupNotificationContent(from: child, actor: node.attrs["participant"]) else {
			return
		}

		let actor = node.attrs["participant"]
		let me = authenticationState?.credentials.me?.id
		let stub: ReceivedMessageStubContent? = if case let .stub(stub) = content {
			stub
		} else {
			nil
		}
		let message = ReceivedMessage(
			id: node.attrs["id"] ?? "",
			from: node.attrs["from"],
			timestamp: node.attrs["t"].flatMap(UInt64.init),
			content: content,
			fromMe: JID.areSameUser(actor ?? node.attrs["from"], me),
			participant: actor,
			keyParticipant: actor,
			stub: stub
		)
		eventContinuation.yield(.receivedMessage(message))
	}

	private func handleDevicesNotification(_ node: BinaryNode) {
		guard case let .nodes(children) = node.content,
			  let change = children.first,
			  let action = DeviceListUpdateAction(rawValue: change.tag) else {
			return
		}

		var userOrder: [String] = []
		var groupedDevices: [String: [WhatsAppDevice]] = [:]

		for deviceNode in change.children(named: "device") {
			guard let rawJID = deviceNode.attrs["jid"], let jid = JID(rawJID) else {
				continue
			}

			if groupedDevices[jid.user] == nil {
				userOrder.append(jid.user)
				groupedDevices[jid.user] = []
			}

			groupedDevices[jid.user]?.append(WhatsAppDevice(
				jid: rawJID,
				user: jid.user,
				server: jid.server,
				device: jid.device
			))
		}

		let updates = userOrder.compactMap { user -> DeviceListUpdate? in
			guard let devices = groupedDevices[user], !devices.isEmpty else {
				return nil
			}

			return DeviceListUpdate(
				user: user,
				action: action,
				deviceHash: change.attrs["device_hash"],
				devices: devices
			)
		}

		if !updates.isEmpty {
			eventContinuation.yield(.deviceListUpdated(updates))
		}
	}

	private func handleEncryptNotification(_ node: BinaryNode) async {
		if node.attrs["from"] == "@s.whatsapp.net" {
			await handlePreKeyCountNotification(node)
			return
		}

		await handleIdentityChangeNotification(node)
	}

	private func handleLinkCodeCompanionRegistrationNotification(_ node: BinaryNode) async {
		guard let processor = linkCodeCompanionRegistrationProcessor,
			  let credentials = authenticationState?.credentials else {
			return
		}

		do {
			let requestID = try messageIDGenerator.generateV2(userID: credentials.me?.id)
			let result = try processor.processLinkCodeCompanionRegistration(
				stanza: node,
				credentials: credentials,
				requestID: requestID
			)
			try await updateCredentials { credentials in
				credentials.advSecretKey = result.advSecretKey
				credentials.registered = true
			}
			try await sendNode(result.reply)
		} catch {
			return
		}
	}

	private func handlePrivacyTokenNotification(_ node: BinaryNode) async {
		guard let keys = authenticationState?.keys,
			  let tokensNode = node.firstChild(named: "tokens") else {
			return
		}

		let storageJID = privacyTokenStorageJID(from: node)
		guard TrustedContactTokenCoding.isRegularUserJID(storageJID) else {
			return
		}

		for tokenNode in tokensNode.children(named: "token") {
			guard tokenNode.attrs["type"] == "trusted_contact",
				  let timestamp = tokenNode.attrs["t"],
				  case let .data(tokenData) = tokenNode.content else {
				continue
			}

			do {
				let existingValues = try await keys.get(.tcToken, ids: [storageJID])
				let existing = existingValues[storageJID].flatMap { try? TrustedContactTokenCoding.decode($0) }
				let existingTimestamp = existing.flatMap { Int($0.timestamp) } ?? 0
				let incomingTimestamp = Int(timestamp) ?? 0
				guard incomingTimestamp > 0, existingTimestamp <= incomingTimestamp else {
					continue
				}

				let token = TrustedContactToken(
					token: tokenData,
					timestamp: timestamp,
					senderTimestamp: existing?.senderTimestamp
				)
				let index = try await TrustedContactTokenCoding.mergedIndexData(in: keys, adding: [storageJID])
				try await keys.set([.tcToken: [
					storageJID: TrustedContactTokenCoding.encode(token),
					TrustedContactTokenCoding.indexKey: index
				]])
			} catch {
				continue
			}
		}
	}

	private func privacyTokenStorageJID(from node: BinaryNode) -> String {
		if let senderLID = node.attrs["sender_lid"].flatMap({ JID($0)?.normalizedUser }),
		   senderLID.isLIDUserJID {
			return senderLID
		}

		return node.attrs["from"].flatMap { JID($0)?.normalizedUser } ?? ""
	}

	private func handlePreKeyCountNotification(_ node: BinaryNode) async {
		guard let count = node.firstChild(named: "count")?.attrs["value"].flatMap(Int.init) else {
			return
		}

		let shouldUpload = count < minimumPreKeyCount
		eventContinuation.yield(.preKeyCountUpdated(PreKeyCountUpdate(
			count: count,
			shouldUploadMorePreKeys: shouldUpload
		)))

		if shouldUpload {
			do {
				if let preKeyUploader {
					if let signalPreKeyUploader = preKeyUploader as? any SignalPreKeyUploading {
						try await signalPreKeyUploader.uploadPreKeys(SignalPreKeyUploadRequest(
							currentCount: count,
							requestedUploadCount: minimumPreKeyCount,
							nativeUploadRequest: try authenticationState?.credentials.nativePreKeyUploadRequest(
								currentServerPreKeyCount: count,
								requestedUploadCount: minimumPreKeyCount
							)
						))
					} else {
						try await preKeyUploader.uploadPreKeys(count: minimumPreKeyCount)
					}
				} else {
					try await uploadPreKeys(count: minimumPreKeyCount)
				}
			} catch {
				eventContinuation.yield(.preKeyUploadFailed(PreKeyUploadFailure(
					currentCount: count,
					requestedUploadCount: minimumPreKeyCount,
					reason: String(describing: error),
					failureReason: preKeyUploadFailureReason(from: error)
				)))
			}
		}
	}

	private func preKeyUploadFailureReason(from error: any Error) -> PreKeyUploadFailureReason {
		switch error as? WhatsAppClientError {
		case .missingAuthenticationState:
			return .missingAuthenticationState
		default:
			return .uploadError(String(describing: error))
		}
	}

	func uploadPreKeys(count: Int) async throws {
		if let preKeyUploadTask {
			try await preKeyUploadTask.value
			return
		}

		let task = Task { [self] in
			try await performPreKeyUpload(count: count)
		}
		preKeyUploadTask = task
		do {
			try await task.value
			preKeyUploadTask = nil
		} catch {
			preKeyUploadTask = nil
			throw error
		}
	}

	private func performPreKeyUpload(count: Int) async throws {
		guard let authenticationState else {
			throw WhatsAppClientError.missingAuthenticationState
		}

		let requestID = try messageIDGenerator.generateV2(userID: authenticationState.credentials.me?.id)
		let request = try PreKeyUploadRequestBuilder.build(
			credentials: authenticationState.credentials,
			count: count,
			requestID: requestID,
			keyPairGenerator: preKeyGenerator
		)
		let encodedPreKeys = try request.preKeys.mapValues(PreKeyUploadRequestBuilder.encode)
		try await authenticationState.keys.set([.preKey: encodedPreKeys.mapValues { Optional($0) }])
		try await updateCredentials { credentials in
			credentials.nextPreKeyID = request.nextPreKeyID
			credentials.firstUnuploadedPreKeyID = request.firstUnuploadedPreKeyID
		}
		_ = try await query(request.node)
	}

	private func handleIdentityChangeNotification(_ node: BinaryNode) async {
		guard let from = node.attrs["from"] else {
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(
				jid: "",
				action: .invalidNotification
			)))
			return
		}

		guard node.firstChild(named: "identity") != nil else {
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(jid: from, action: .noIdentityNode)))
			return
		}

		if let jid = JID(from), let device = jid.device, device != 0 {
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(
				jid: from,
				action: .skippedCompanionDevice
			)))
			return
		}

		let me = authenticationState?.credentials.me
		if JID.areSameUser(from, me?.id) || JID.areSameUser(from, me?.lid) {
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(jid: from, action: .skippedSelfPrimary)))
			return
		}

		if !StringPresence.isNullOrEmpty(node.attrs["offline"]) {
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(jid: from, action: .skippedOffline)))
			return
		}

		guard let signalSessionPreparer else {
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(jid: from, action: .noSessionPreparer)))
			return
		}

		await reissueTrustedContactTokenAfterIdentityChange(from: from)

		do {
			_ = try await signalSessionPreparer.assertSessions(for: [from], force: true)
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(
				jid: from,
				action: .sessionRefreshRequested
			)))
		} catch {
			eventContinuation.yield(.identityChanged(IdentityChangeUpdate(jid: from, action: .sessionRefreshFailed)))
		}
	}

	private func groupNotificationContent(from child: BinaryNode, actor: String?) -> ReceivedMessageContent? {
		switch child.tag {
		case "ephemeral", "not_ephemeral":
			let expiration = UInt32(child.attrs["expiration"] ?? "0")
			return .ephemeralSetting(ReceivedEphemeralSettingContent(
				expirationSeconds: expiration,
				settingTimestampSeconds: nil,
				disappearingMode: nil
			))
		case "subject":
			return .stub(ReceivedMessageStubContent(
				type: .groupChangeSubject,
				parameters: child.attrs["subject"].map { [$0] } ?? []
			))
		case "description":
			return .stub(ReceivedMessageStubContent(
				type: .groupChangeDescription,
				parameters: child.childString(named: "body").map { [$0] } ?? []
			))
		case "announcement", "not_announcement":
			return .stub(ReceivedMessageStubContent(
				type: .groupChangeAnnounce,
				parameters: [child.tag == "announcement" ? "on" : "off"]
			))
		case "locked", "unlocked":
			return .stub(ReceivedMessageStubContent(
				type: .groupChangeRestrict,
				parameters: [child.tag == "locked" ? "on" : "off"]
			))
		case "invite":
			return .stub(ReceivedMessageStubContent(
				type: .groupChangeInviteLink,
				parameters: child.attrs["code"].map { [$0] } ?? []
			))
		case "member_add_mode":
			if case let .string(addMode) = child.content {
				return .stub(ReceivedMessageStubContent(type: .groupMemberAddMode, parameters: [addMode]))
			}
			if case let .data(data) = child.content,
			   let addMode = String(data: data, encoding: .utf8) {
				return .stub(ReceivedMessageStubContent(type: .groupMemberAddMode, parameters: [addMode]))
			}
			return nil
		case "membership_approval_mode":
			return child.firstChild(named: "group_join")?.attrs["state"].map {
				.stub(ReceivedMessageStubContent(type: .groupMembershipJoinApprovalMode, parameters: [$0]))
			}
		case "modify":
			return .stub(ReceivedMessageStubContent(
				type: .groupParticipantChangeNumber,
				parameters: child.children(named: "participant").compactMap { $0.attrs["jid"] }
			))
		case "created_membership_requests":
			let identity = groupMembershipRequestIdentity(child: child, actor: actor)
			var parameters = [identity, "created"]
			if let method = child.attrs["request_method"] {
				parameters.append(method)
			}
			return .stub(ReceivedMessageStubContent(
				type: .groupMembershipJoinApprovalRequestNonAdminAdd,
				parameters: parameters
			))
		case "revoked_membership_requests":
			let identity = groupMembershipRequestIdentity(child: child, actor: actor)
			let affected = child.firstChild(named: "participant")?.attrs["jid"] ?? actor
			let state = JID.areSameUser(affected, actor) ? "revoked" : "rejected"
			return .stub(ReceivedMessageStubContent(
				type: .groupMembershipJoinApprovalRequestNonAdminAdd,
				parameters: [identity, state]
			))
		case "promote", "demote", "remove", "add", "leave":
			var stubType = groupParticipantStubType(for: child.tag)
			let participants = child.children(named: "participant")
			if child.tag == "remove", participants.count == 1,
			   JID.areSameUser(participants[0].attrs["jid"], actor) {
				stubType = .groupParticipantLeave
			}

			return .stub(ReceivedMessageStubContent(
				type: stubType,
				parameters: participants.compactMap(groupParticipantParameter)
			))
		default:
			return nil
		}
	}

	private func groupParticipantStubType(for tag: String) -> ReceivedMessageStubType {
		switch tag {
		case "promote":
			return .groupParticipantPromote
		case "demote":
			return .groupParticipantDemote
		case "remove":
			return .groupParticipantRemove
		case "leave":
			return .groupParticipantLeave
		default:
			return .groupParticipantAdd
		}
	}

	private func groupParticipantParameter(_ participant: BinaryNode) -> String? {
		guard let jid = participant.attrs["jid"] else {
			return nil
		}

		var fields = ["\"id\":\"\(jid)\""]
		if let phoneNumber = participant.attrs["phone_number"] {
			fields.append("\"phoneNumber\":\"\(phoneNumber)\"")
		}
		if let lid = participant.attrs["lid"] {
			fields.append("\"lid\":\"\(lid)\"")
		}
		if let username = participant.attrs["participant_username"] ?? participant.attrs["username"] {
			fields.append("\"username\":\"\(username)\"")
		}
		if let admin = participant.attrs["type"] {
			fields.append("\"admin\":\"\(admin)\"")
		}
		return "{\(fields.joined(separator: ","))}"
	}

	private func groupMembershipRequestIdentity(child: BinaryNode, actor: String?) -> String {
		let participant = child.firstChild(named: "participant")
		let lid = participant?.attrs["jid"] ?? actor ?? ""
		let phoneNumber = participant?.attrs["phone_number"] ?? lid
		return "{\"lid\":\"\(lid)\",\"pn\":\"\(phoneNumber)\"}"
	}

	private func mediaRetryUpdate(from node: BinaryNode) -> MessageMediaUpdate? {
		guard let rmr = node.firstChild(named: "rmr") else {
			return nil
		}

		let key = WhatsAppMessageKey(
			remoteJID: rmr.attrs["jid"],
			fromMe: rmr.attrs["from_me"] == "true",
			id: node.attrs["id"],
			participant: rmr.attrs["participant"]
		)

		if let error = node.firstChild(named: "error") {
			let errorCode = error.attrs["code"].flatMap(Int.init)
			return MessageMediaUpdate(
				key: key,
				errorCode: errorCode,
				errorStatusCode: errorCode.flatMap(MediaRetryStatusCodeMapper.statusCode(for:))
			)
		}

		let encrypt = node.firstChild(named: "encrypt")
		guard let ciphertext = encrypt?.childData(named: "enc_p"),
			  let iv = encrypt?.childData(named: "enc_iv") else {
			return MessageMediaUpdate(key: key, errorCode: 2, errorStatusCode: 404)
		}

		return MessageMediaUpdate(key: key, media: RetriedMedia(ciphertext: ciphertext, iv: iv))
	}
}
