import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client app-state mutation events")
struct WhatsAppClientAppStateMutationEventTests {
	@Test("sync app state emits local message delete updates")
	func syncAppStateEmitsLocalMessageDeleteUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(.deleteForMe(
			jid: "123@s.whatsapp.net",
			messageID: "3EB0DELETE",
			fromMe: true,
			timestamp: 1_800_000_000,
			deleteMedia: false
		))
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .messagesDeleted(MessageDeleteUpdate(keys: [
			WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: true, id: "3EB0DELETE")
		])))
	}

	@Test("sync app state emits starred message updates")
	func syncAppStateEmitsStarredMessageUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(.star(
			jid: "123@s.whatsapp.net",
			messageID: "3EB0STAR",
			fromMe: false,
			starred: true
		))
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .messagesUpdated([
			ReceivedMessageUpdate(
				key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "3EB0STAR"),
				status: nil,
				timestamp: nil,
				starred: true
			)
		]))
	}

	@Test("sync app state emits chat delete updates")
	func syncAppStateEmitsChatDeleteUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(.deleteChat(
			jid: "123@s.whatsapp.net",
			messageRange: AppStateChatMessageRange(
				messages: [
					AppStateChatRangeMessage(
						key: WhatsAppMessageKey(remoteJID: "123@s.whatsapp.net", fromMe: false, id: "3EB0CHAT"),
						timestamp: 1_800_000_000
					)
				]
			).proto()
		))
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .chatsDeleted(ChatDeleteUpdate(ids: ["123@s.whatsapp.net"])))
	}

	@Test("sync app state emits contact updates")
	func syncAppStateEmitsContactUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		let patch = try encodedMutationPatch(.contact(
			jid: "123@s.whatsapp.net",
			contact: ChatModificationContact(
				fullName: "Americo Junior",
				firstName: "Americo",
				lidJid: "123@lid",
				pnJid: "123@s.whatsapp.net",
				username: "americo"
			)
		))
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .contactsUpdated([
			ContactUpdate(
				id: "123@s.whatsapp.net",
				name: "Americo Junior",
				username: "americo",
				lid: "123@lid",
				phoneNumber: "123@s.whatsapp.net"
			)
		]))
		#expect(await events.next() == .lidMappingUpdated(LIDMapping(pn: "123@s.whatsapp.net", lid: "123@lid")))
	}

	@Test("sync app state emits PN for LID chat mapping updates")
	func syncAppStateEmitsPNForLIDChatMappingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var mapping = Proto_SyncActionValue.PnForLidChatAction()
		mapping.pnJid = "123@s.whatsapp.net"
		var action = Proto_SyncActionValue()
		action.pnForLidChatAction = mapping
		let patch = try encodedMutationPatch(
			action: action,
			index: ["pn_for_lid_chat", "123@lid"],
			type: .regularHigh
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .lidMappingUpdated(LIDMapping(pn: "123@s.whatsapp.net", lid: "123@lid")))
	}

	@Test("sync app state emits chat lock updates")
	func syncAppStateEmitsChatLockUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var lock = Proto_SyncActionValue.LockChatAction()
		lock.locked = true
		var action = Proto_SyncActionValue()
		action.lockChatAction = lock
		let patch = try encodedMutationPatch(
			action: action,
			index: ["lock_chat", "123@s.whatsapp.net"],
			type: .regularHigh
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.regularHigh])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "regular_high",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .chatLockUpdated(ChatLockUpdate(id: "123@s.whatsapp.net", locked: true)))
	}

	@Test("sync app state emits locale setting updates")
	func syncAppStateEmitsLocaleSettingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var locale = Proto_SyncActionValue.LocaleSetting()
		locale.locale = "pt_MZ"
		var action = Proto_SyncActionValue()
		action.localeSetting = locale
		let patch = try encodedMutationPatch(action: action, index: ["setting_locale"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .settingsUpdated(SettingsUpdate(setting: "locale", value: .string("pt_MZ"))))
	}

	@Test("sync app state emits time format setting updates")
	func syncAppStateEmitsTimeFormatSettingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var timeFormat = Proto_SyncActionValue.TimeFormatAction()
		timeFormat.isTwentyFourHourFormatEnabled = true
		var action = Proto_SyncActionValue()
		action.timeFormatAction = timeFormat
		let patch = try encodedMutationPatch(action: action, index: ["setting_time_format"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .settingsUpdated(SettingsUpdate(setting: "timeFormat", value: .bool(true))))
	}

	@Test("sync app state emits relay all calls setting updates")
	func syncAppStateEmitsRelayAllCallsSettingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var relay = Proto_SyncActionValue.PrivacySettingRelayAllCalls()
		relay.isEnabled = true
		var action = Proto_SyncActionValue()
		action.privacySettingRelayAllCalls = relay
		let patch = try encodedMutationPatch(action: action, index: ["setting_relay_all_calls"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .settingsUpdated(SettingsUpdate(
			setting: "privacySettingRelayAllCalls",
			value: .bool(true)
		)))
	}

	@Test("sync app state emits status privacy setting updates")
	func syncAppStateEmitsStatusPrivacySettingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var statusPrivacy = Proto_SyncActionValue.StatusPrivacyAction()
		statusPrivacy.mode = .closeFriends
		statusPrivacy.userJid = ["111@s.whatsapp.net", "222@s.whatsapp.net"]
		var action = Proto_SyncActionValue()
		action.statusPrivacy = statusPrivacy
		let patch = try encodedMutationPatch(action: action, index: ["setting_status_privacy"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .settingsUpdated(SettingsUpdate(
			setting: "statusPrivacy",
			value: .statusPrivacy(StatusPrivacyUpdate(
				mode: 3,
				userJIDs: ["111@s.whatsapp.net", "222@s.whatsapp.net"]
			))
		)))
	}

	@Test("sync app state emits disabled link previews setting updates")
	func syncAppStateEmitsDisabledLinkPreviewsSettingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var previews = Proto_SyncActionValue.PrivacySettingDisableLinkPreviewsAction()
		previews.isPreviewsDisabled = true
		var action = Proto_SyncActionValue()
		action.privacySettingDisableLinkPreviewsAction = previews
		let patch = try encodedMutationPatch(action: action, index: ["setting_disable_link_previews"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .settingsUpdated(SettingsUpdate(setting: "disableLinkPreviews", value: .bool(true))))
	}

	@Test("sync app state emits notification activity setting updates")
	func syncAppStateEmitsNotificationActivitySettingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var notification = Proto_SyncActionValue.NotificationActivitySettingAction()
		notification.notificationActivitySetting = .highlights
		var action = Proto_SyncActionValue()
		action.notificationActivitySettingAction = notification
		let patch = try encodedMutationPatch(action: action, index: ["setting_notification_activity"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .settingsUpdated(SettingsUpdate(
			setting: "notificationActivitySetting",
			value: .int(2)
		)))
	}

	@Test("sync app state emits channels recommendation setting updates")
	func syncAppStateEmitsChannelsRecommendationSettingUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var recommendation = Proto_SyncActionValue.PrivacySettingChannelsPersonalisedRecommendationAction()
		recommendation.isUserOptedOut = true
		var action = Proto_SyncActionValue()
		action.privacySettingChannelsPersonalisedRecommendationAction = recommendation
		let patch = try encodedMutationPatch(action: action, index: ["setting_channels_recommendation"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .settingsUpdated(SettingsUpdate(
			setting: "channelsPersonalisedRecommendation",
			value: .bool(true)
		)))
	}

	@Test("sync app state updates credentials from push name settings")
	func syncAppStateUpdatesCredentialsFromPushNameSettings() async throws {
		let (client, transport) = try appStateMutationClient()
		var pushName = Proto_SyncActionValue.PushNameSetting()
		pushName.name = "Americo Swift"
		var action = Proto_SyncActionValue()
		action.pushNameSetting = pushName
		let patch = try encodedMutationPatch(action: action, index: ["setting_pushName"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		guard case .credentialsUpdated(let credentials)? = await events.next() else {
			Issue.record("expected credentialsUpdated")
			return
		}
		#expect(credentials.me?.name == "Americo Swift")
	}

	@Test("sync app state updates credentials from unarchive chat settings")
	func syncAppStateUpdatesCredentialsFromUnarchiveChatSettings() async throws {
		let (client, transport) = try appStateMutationClient()
		var unarchive = Proto_SyncActionValue.UnarchiveChatsSetting()
		unarchive.unarchiveChats = true
		var action = Proto_SyncActionValue()
		action.unarchiveChatsSetting = unarchive
		let patch = try encodedMutationPatch(action: action, index: ["setting_unarchive_chats"], type: .criticalUnblockLow)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		guard case .credentialsUpdated(let credentials)? = await events.next() else {
			Issue.record("expected credentialsUpdated")
			return
		}
		#expect(credentials.accountSettings.unarchiveChats)
	}

	@Test("sync app state emits LID contact updates")
	func syncAppStateEmitsLIDContactUpdates() async throws {
		let (client, transport) = try appStateMutationClient()
		var contact = Proto_SyncActionValue.LidContactAction()
		contact.firstName = "Americo"
		contact.username = "americo"
		var action = Proto_SyncActionValue()
		action.lidContactAction = contact
		let patch = try encodedMutationPatch(
			action: action,
			index: ["lid_contact", "123@lid"],
			type: .criticalUnblockLow
		)
		try await client.connect()
		var events = client.events.makeAsyncIterator()

		let task = Task {
			try await client.syncAppState(collections: [.criticalUnblockLow])
		}
		let request = try await transport.waitForSentNode()
		await enqueueMutationPatchResponse(
			patch,
			collection: "critical_unblock_low",
			requestID: try #require(request.attrs["id"]),
			transport: transport
		)

		_ = try await task.value
		#expect(await events.next() == .contactsUpdated([
			ContactUpdate(id: "123@lid", name: "Americo", username: "americo", lid: "123@lid")
		]))
	}
}

func appStateMutationClient() throws -> (WhatsAppClient, MockProfileWebSocketTransport) {
	var appStateKeyData = Proto_Message.AppStateSyncKeyData()
	appStateKeyData.keyData = Data((0..<32).map(UInt8.init))
	let keys = InMemorySignalKeyStore(storage: [
		.appStateSyncKey: ["AQIDBAUGBwg=": try appStateKeyData.serializedData()]
	])
	let transport = MockProfileWebSocketTransport()
	let client = WhatsAppClient(
		authenticationState: AuthenticationState(credentials: appStateCredentials(), keys: keys),
		transportFactory: { _ in transport }
	)
	return (client, transport)
}

func encodedMutationPatch(_ modification: ChatModification) throws -> Proto_SyncdPatch {
	try encodedMutationPatch(patch: ChatModificationPatchBuilder.patch(for: modification))
}

func encodedMutationPatch(
	action: Proto_SyncActionValue,
	index: [String],
	type: ChatModificationPatchType
) throws -> Proto_SyncdPatch {
	try encodedMutationPatch(patch: ChatModificationPatch(
		syncAction: action,
		index: index,
		type: type,
		apiVersion: 1,
		operation: .set
	))
}

func encodedMutationPatch(patch: ChatModificationPatch) throws -> Proto_SyncdPatch {
	let encoded = try AppStatePatchEncoder.encode(
		patch,
		keyID: try appStateHexData("0102030405060708"),
		keys: try appStateFixtureKeys(),
		state: AppStatePatchState(),
		iv: try appStateHexData("202122232425262728292a2b2c2d2e2f"),
		hashMixer: NativeAppStatePatchHashMixer()
	)
	var patch = encoded.patch
	patch.version.version = encoded.state.version
	return patch
}

func enqueueMutationPatchResponse(
	_ patch: Proto_SyncdPatch,
	collection: String,
	requestID: String,
	transport: MockProfileWebSocketTransport
) async {
	await transport.enqueueInbound(BinaryNode(
		tag: "iq",
		attrs: ["id": requestID, "type": "result"],
		content: .nodes([
			BinaryNode(tag: "sync", content: .nodes([
				BinaryNode(
					tag: "collection",
					attrs: ["name": collection, "version": "0", "has_more_patches": "false"],
					content: .nodes([
						BinaryNode(tag: "patch", content: .data(try! patch.serializedData()))
					])
				)
			]))
		])
	))
}
