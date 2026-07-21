import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client business")
struct WhatsAppClientBusinessTests {
	@Test("queries and parses a business profile")
	func queriesAndParsesBusinessProfile() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessProfile(for: "258840000000@c.us", requestID: "business-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "business-1")
		#expect(request.attrs["to"] == "s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:biz")
		let businessProfile = try #require(request.firstChild(named: "business_profile"))
		#expect(businessProfile.attrs["v"] == "244")
		#expect(businessProfile.firstChild(named: "profile")?.attrs["jid"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "business-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "business_profile", content: .nodes([
					BinaryNode(
						tag: "profile",
						attrs: ["jid": "258840000000@s.whatsapp.net"],
						content: .nodes([
							BinaryNode(tag: "address", content: .string("Maputo")),
							BinaryNode(tag: "description", content: .string("Swift commerce")),
							BinaryNode(tag: "website", content: .string("https://example.com")),
							BinaryNode(tag: "email", content: .string("sales@example.com")),
							BinaryNode(tag: "categories", content: .nodes([
								BinaryNode(tag: "category", content: .string("Software"))
							])),
							BinaryNode(tag: "business_hours", attrs: ["timezone": "Africa/Maputo"], content: .nodes([
								BinaryNode(
									tag: "business_hours_config",
									attrs: ["day_of_week": "mon", "mode": "open", "open_time": "540", "close_time": "1020"]
								)
							]))
						])
					)
				]))
			])
		))

		let profile = try #require(try await task.value)
		#expect(profile.wid == "258840000000@s.whatsapp.net")
		#expect(profile.address == "Maputo")
		#expect(profile.description == "Swift commerce")
		#expect(profile.website == ["https://example.com"])
		#expect(profile.email == "sales@example.com")
		#expect(profile.category == "Software")
		#expect(profile.businessHours.timezone == "Africa/Maputo")
		#expect(profile.businessHours.config == [
			BusinessHoursConfig(dayOfWeek: "mon", mode: "open", openTime: 540, closeTime: 1020)
		])
	}

	@Test("returns nil when business profile is absent")
	func returnsNilWhenBusinessProfileIsAbsent() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessProfile(for: "258840000000@s.whatsapp.net", requestID: "business-2")
		}
		_ = try await transport.waitForSentNode()

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "business-2", "type": "result"]))
		#expect(try await task.value == nil)
	}

	@Test("Baileys business profile alias queries profile")
	func baileysBusinessProfileAliasQueriesProfile() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.getBusinessProfile(for: "258840000000@c.us", requestID: "business-alias-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "business-alias-1")
		#expect(request.attrs["xmlns"] == "w:biz")
		#expect(request.firstChild(named: "business_profile")?.firstChild(named: "profile")?.attrs["jid"] == "258840000000@s.whatsapp.net")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "business-alias-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "business_profile", content: .nodes([
					BinaryNode(tag: "profile", attrs: ["jid": "258840000000@s.whatsapp.net"])
				]))
			])
		))

		#expect(try await task.value?.wid == "258840000000@s.whatsapp.net")
	}

	@Test("updates business profile fields and websites")
	func updatesBusinessProfileFieldsAndWebsites() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.updateBusinessProfile(
				BusinessProfileUpdate(
					address: "Av. Julius Nyerere",
					websites: ["https://example.com", "https://shop.example.com"],
					email: "sales@example.com",
					description: "Swift commerce"
				),
				requestID: "business-update-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "business-update-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:biz")
		let profile = try #require(request.firstChild(named: "business_profile"))
		#expect(profile.attrs["v"] == "3")
		#expect(profile.attrs["mutation_type"] == "delta")
		#expect(profile.childString(named: "address") == "Av. Julius Nyerere")
		#expect(profile.childString(named: "email") == "sales@example.com")
		#expect(profile.childString(named: "description") == "Swift commerce")
		#expect(profile.children(named: "website").map(\.childText) == [
			"https://example.com",
			"https://shop.example.com"
		])

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "business-update-1", "type": "result"]))
		try await task.value
	}

	@Test("Baileys business profile update alias sends delta mutation")
	func baileysBusinessProfileUpdateAliasSendsDeltaMutation() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.updateBussinesProfile(
				BusinessProfileUpdate(description: "Swift commerce"),
				requestID: "business-update-alias"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "business-update-alias")
		#expect(request.firstChild(named: "business_profile")?.childString(named: "description") == "Swift commerce")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "business-update-alias", "type": "result"]))
		try await task.value
	}

	@Test("updates business profile hours")
	func updatesBusinessProfileHours() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.updateBusinessProfile(
				BusinessProfileUpdate(hours: BusinessProfileHoursUpdate(
					timezone: "Africa/Maputo",
					days: [
						BusinessProfileHoursDay(day: .mon, mode: .specificHours, openTimeInMinutes: 540, closeTimeInMinutes: 1020),
						BusinessProfileHoursDay(day: .sun, mode: .open24h)
					]
				)),
				requestID: "business-update-2"
			)
		}
		let request = try await transport.waitForSentNode()
		let hours = try #require(request.firstChild(named: "business_profile")?.firstChild(named: "business_hours"))
		#expect(hours.attrs["timezone"] == "Africa/Maputo")
		let configs = hours.children(named: "business_hours_config")
		#expect(configs.count == 2)
		#expect(configs[0].attrs["day_of_week"] == "mon")
		#expect(configs[0].attrs["mode"] == "specific_hours")
		#expect(configs[0].attrs["open_time"] == "540")
		#expect(configs[0].attrs["close_time"] == "1020")
		#expect(configs[1].attrs["day_of_week"] == "sun")
		#expect(configs[1].attrs["mode"] == "open_24h")
		#expect(configs[1].attrs["open_time"] == nil)

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "business-update-2", "type": "result"]))
		try await task.value
	}

	@Test("removes business cover photo")
	func removesBusinessCoverPhoto() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.removeBusinessCoverPhoto(id: "cover-1", requestID: "cover-remove-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "cover-remove-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:biz")
		let profile = try #require(request.firstChild(named: "business_profile"))
		#expect(profile.attrs["v"] == "3")
		#expect(profile.attrs["mutation_type"] == "delta")
		let coverPhoto = try #require(profile.firstChild(named: "cover_photo"))
		#expect(coverPhoto.attrs["op"] == "delete")
		#expect(coverPhoto.attrs["id"] == "cover-1")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "cover-remove-1", "type": "result"]))
		try await task.value
	}

	@Test("Baileys cover photo remove alias sends delete mutation")
	func baileysCoverPhotoRemoveAliasSendsDeleteMutation() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.removeCoverPhoto(id: "cover-alias", requestID: "cover-remove-alias")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "cover-remove-alias")
		let coverPhoto = try #require(request.firstChild(named: "business_profile")?.firstChild(named: "cover_photo"))
		#expect(coverPhoto.attrs["op"] == "delete")
		#expect(coverPhoto.attrs["id"] == "cover-alias")

		await transport.enqueueInbound(BinaryNode(tag: "iq", attrs: ["id": "cover-remove-alias", "type": "result"]))
		try await task.value
	}

	@Test("queries and parses business catalog")
	func queriesAndParsesBusinessCatalog() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessCatalog(
				for: "258840000000@c.us",
				limit: 3,
				cursor: "next-cursor",
				requestID: "catalog-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "catalog-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:biz:catalog")
		let catalog = try #require(request.firstChild(named: "product_catalog"))
		#expect(catalog.attrs["jid"] == "258840000000@s.whatsapp.net")
		#expect(catalog.attrs["allow_shop_source"] == "true")
		#expect(catalog.childString(named: "limit") == "3")
		#expect(catalog.childString(named: "width") == "100")
		#expect(catalog.childString(named: "height") == "100")
		#expect(catalog.childString(named: "after") == "next-cursor")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "catalog-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "product_catalog", content: .nodes([
					BinaryNode(tag: "product", attrs: ["is_hidden": "true"], content: .nodes([
						BinaryNode(tag: "id", content: .string("prod-1")),
						BinaryNode(tag: "name", content: .string("Coffee")),
						BinaryNode(tag: "retailer_id", content: .string("sku-1")),
						BinaryNode(tag: "url", content: .string("https://shop.example.com/coffee")),
						BinaryNode(tag: "description", content: .string("Ground coffee")),
						BinaryNode(tag: "price", content: .string("1500")),
						BinaryNode(tag: "currency", content: .string("MZN")),
						BinaryNode(tag: "media", content: .nodes([
							BinaryNode(tag: "image", content: .nodes([
								BinaryNode(tag: "request_image_url", content: .string("https://mmg.whatsapp.net/request.jpg")),
								BinaryNode(tag: "original_image_url", content: .string("https://mmg.whatsapp.net/original.jpg"))
							]))
						])),
						BinaryNode(tag: "status_info", content: .nodes([
							BinaryNode(tag: "status", content: .string("approved"))
						]))
					])),
					BinaryNode(tag: "paging", content: .nodes([
						BinaryNode(tag: "after", content: .string("after-2"))
					]))
				]))
			])
		))

		let result = try await task.value
		#expect(result.nextPageCursor == "after-2")
		#expect(result.products == [
			BusinessProduct(
				id: "prod-1",
				name: "Coffee",
				retailerID: "sku-1",
				url: "https://shop.example.com/coffee",
				description: "Ground coffee",
				price: 1500,
				currency: "MZN",
				isHidden: true,
				imageURLs: BusinessProductImageURLs(
					requested: "https://mmg.whatsapp.net/request.jpg",
					original: "https://mmg.whatsapp.net/original.jpg"
				),
				reviewStatus: ["whatsapp": "approved"],
				availability: "in stock"
			)
		])
	}

	@Test("Baileys catalog alias sends product catalog query")
	func baileysCatalogAliasSendsProductCatalogQuery() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.getCatalog(for: "258840000000@c.us", limit: 2, cursor: "cursor", requestID: "catalog-alias")
		}
		let request = try await transport.waitForSentNode()
		let catalog = try #require(request.firstChild(named: "product_catalog"))
		#expect(catalog.attrs["jid"] == "258840000000@s.whatsapp.net")
		#expect(catalog.childString(named: "limit") == "2")
		#expect(catalog.childString(named: "after") == "cursor")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "catalog-alias", "type": "result"],
			content: .nodes([BinaryNode(tag: "product_catalog")])
		))

		#expect(try await task.value.products.isEmpty)
	}

	@Test("queries and parses business collections")
	func queriesAndParsesBusinessCollections() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessCollections(for: "258840000000@c.us", limit: 7, requestID: "collections-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "collections-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "w:biz:catalog")
		#expect(request.attrs["smax_id"] == "35")
		let collections = try #require(request.firstChild(named: "collections"))
		#expect(collections.attrs["biz_jid"] == "258840000000@s.whatsapp.net")
		#expect(collections.childString(named: "collection_limit") == "7")
		#expect(collections.childString(named: "item_limit") == "7")
		#expect(collections.childString(named: "width") == "100")
		#expect(collections.childString(named: "height") == "100")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "collections-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "collections", content: .nodes([
					BinaryNode(tag: "collection", content: .nodes([
						BinaryNode(tag: "id", content: .string("col-1")),
						BinaryNode(tag: "name", content: .string("Featured")),
						BinaryNode(tag: "status_info", content: .nodes([
							BinaryNode(tag: "status", content: .string("approved")),
							BinaryNode(tag: "can_appeal", content: .string("true"))
						])),
						BinaryNode(tag: "product", content: .nodes([
							BinaryNode(tag: "id", content: .string("prod-2")),
							BinaryNode(tag: "name", content: .string("Tea")),
							BinaryNode(tag: "description", content: .string("Green tea")),
							BinaryNode(tag: "price", content: .string("500")),
							BinaryNode(tag: "currency", content: .string("MZN")),
							BinaryNode(tag: "media", content: .nodes([
								BinaryNode(tag: "image", content: .nodes([
									BinaryNode(tag: "request_image_url", content: .string("https://mmg.whatsapp.net/tea-request.jpg")),
									BinaryNode(tag: "original_image_url", content: .string("https://mmg.whatsapp.net/tea-original.jpg"))
								]))
							])),
							BinaryNode(tag: "status_info", content: .nodes([
								BinaryNode(tag: "status", content: .string("approved"))
							]))
						]))
					]))
				]))
			])
		))

		let result = try await task.value
		#expect(result.collections.count == 1)
		#expect(result.collections[0].id == "col-1")
		#expect(result.collections[0].name == "Featured")
		#expect(result.collections[0].status == BusinessCatalogStatus(status: "approved", canAppeal: true))
		#expect(result.collections[0].products.map(\.id) == ["prod-2"])
	}

	@Test("Baileys collections alias sends collections query")
	func baileysCollectionsAliasSendsCollectionsQuery() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.getCollections(for: "258840000000@c.us", limit: 4, requestID: "collections-alias")
		}
		let request = try await transport.waitForSentNode()
		let collections = try #require(request.firstChild(named: "collections"))
		#expect(collections.attrs["biz_jid"] == "258840000000@s.whatsapp.net")
		#expect(collections.childString(named: "collection_limit") == "4")
		#expect(collections.childString(named: "item_limit") == "4")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "collections-alias", "type": "result"],
			content: .nodes([BinaryNode(tag: "collections")])
		))

		#expect(try await task.value.collections.isEmpty)
	}

	@Test("queries and parses business order details")
	func queriesAndParsesBusinessOrderDetails() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessOrderDetails(
				orderID: "order-1",
				tokenBase64: "token-base64",
				requestID: "order-details-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "order-details-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "get")
		#expect(request.attrs["xmlns"] == "fb:thrift_iq")
		#expect(request.attrs["smax_id"] == "5")
		let order = try #require(request.firstChild(named: "order"))
		#expect(order.attrs["op"] == "get")
		#expect(order.attrs["id"] == "order-1")
		#expect(order.firstChild(named: "image_dimensions")?.childString(named: "width") == "100")
		#expect(order.firstChild(named: "image_dimensions")?.childString(named: "height") == "100")
		#expect(order.childString(named: "token") == "token-base64")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "order-details-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "order", content: .nodes([
					BinaryNode(tag: "price", content: .nodes([
						BinaryNode(tag: "total", content: .string("2500")),
						BinaryNode(tag: "currency", content: .string("MZN"))
					])),
					BinaryNode(tag: "product", content: .nodes([
						BinaryNode(tag: "id", content: .string("prod-1")),
						BinaryNode(tag: "name", content: .string("Coffee")),
						BinaryNode(tag: "price", content: .string("1500")),
						BinaryNode(tag: "currency", content: .string("MZN")),
						BinaryNode(tag: "quantity", content: .string("2")),
						BinaryNode(tag: "image", content: .nodes([
							BinaryNode(tag: "url", content: .string("https://mmg.whatsapp.net/order.jpg"))
						]))
					]))
				]))
			])
		))

		let details = try await task.value
		#expect(details.price == BusinessOrderPrice(currency: "MZN", total: 2500))
		#expect(details.products == [
			BusinessOrderProduct(
				id: "prod-1",
				imageURL: "https://mmg.whatsapp.net/order.jpg",
				name: "Coffee",
				quantity: 2,
				currency: "MZN",
				price: 1500
			)
		])
	}

	@Test("Baileys order details alias sends order query")
	func baileysOrderDetailsAliasSendsOrderQuery() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.getOrderDetails(
				orderID: "order-alias",
				tokenBase64: "token",
				requestID: "order-alias-1"
			)
		}
		let request = try await transport.waitForSentNode()
		let order = try #require(request.firstChild(named: "order"))
		#expect(order.attrs["op"] == "get")
		#expect(order.attrs["id"] == "order-alias")
		#expect(order.childString(named: "token") == "token")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "order-alias-1", "type": "result"],
			content: .nodes([BinaryNode(tag: "order")])
		))

		#expect(try await task.value.products.isEmpty)
	}

}
