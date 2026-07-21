extension WhatsAppClient {
	public func businessProfile(for jid: String, requestID: String? = nil) async throws -> BusinessProfile? {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let normalizedJID = JID(jid)?.normalizedUser ?? jid
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "s.whatsapp.net",
				"xmlns": "w:biz",
				"type": "get"
			],
			content: .nodes([
				BinaryNode(
					tag: "business_profile",
					attrs: ["v": "244"],
					content: .nodes([
						BinaryNode(tag: "profile", attrs: ["jid": normalizedJID])
					])
				)
			])
		))

		guard let profile = result.firstChild(named: "business_profile")?.firstChild(named: "profile") else {
			return nil
		}

		let website = profile.childString(named: "website").map { [$0] } ?? []
		let businessHoursNode = profile.firstChild(named: "business_hours")
		let configs = businessHoursNode?.children(named: "business_hours_config").map { config in
			BusinessHoursConfig(
				dayOfWeek: config.attrs["day_of_week"] ?? "",
				mode: config.attrs["mode"] ?? "",
				openTime: config.attrs["open_time"].flatMap(Int.init),
				closeTime: config.attrs["close_time"].flatMap(Int.init)
			)
		} ?? []

		return BusinessProfile(
			wid: profile.attrs["jid"],
			address: profile.childString(named: "address"),
			description: profile.childString(named: "description") ?? "",
			website: website,
			email: profile.childString(named: "email"),
			category: profile.firstChild(named: "categories")?.childString(named: "category"),
			businessHours: BusinessHours(timezone: businessHoursNode?.attrs["timezone"], config: configs)
		)
	}

	public func getBusinessProfile(for jid: String, requestID: String? = nil) async throws -> BusinessProfile? {
		try await businessProfile(for: jid, requestID: requestID)
	}

	public func updateBusinessProfile(_ update: BusinessProfileUpdate, requestID: String? = nil) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var nodes: [BinaryNode] = []
		if let address = update.address {
			nodes.append(BinaryNode(tag: "address", content: .string(address)))
		}

		if let email = update.email {
			nodes.append(BinaryNode(tag: "email", content: .string(email)))
		}

		if let description = update.description {
			nodes.append(BinaryNode(tag: "description", content: .string(description)))
		}

		for website in update.websites ?? [] {
			nodes.append(BinaryNode(tag: "website", content: .string(website)))
		}

		if let hours = update.hours {
			nodes.append(BinaryNode(
				tag: "business_hours",
				attrs: ["timezone": hours.timezone],
				content: .nodes(hours.days.map { day in
					var attrs: [(String, String)] = [
						("day_of_week", day.day.rawValue),
						("mode", day.mode.rawValue)
					]
					if day.mode == .specificHours {
						if let openTime = day.openTimeInMinutes {
							attrs.append(("open_time", String(openTime)))
						}

						if let closeTime = day.closeTimeInMinutes {
							attrs.append(("close_time", String(closeTime)))
						}
					}

					return BinaryNode(tag: "business_hours_config", attrs: BinaryNodeAttributes(attrs))
				})
			))
		}

		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "w:biz"
			],
			content: .nodes([
				BinaryNode(
					tag: "business_profile",
					attrs: ["v": "3", "mutation_type": "delta"],
					content: .nodes(nodes)
				)
			])
		))
	}

	public func updateBussinesProfile(_ update: BusinessProfileUpdate, requestID: String? = nil) async throws {
		try await updateBusinessProfile(update, requestID: requestID)
	}

	public func removeBusinessCoverPhoto(id coverPhotoID: String, requestID: String? = nil) async throws {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		_ = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "w:biz"
			],
			content: .nodes([
				BinaryNode(
					tag: "business_profile",
					attrs: ["v": "3", "mutation_type": "delta"],
					content: .nodes([
						BinaryNode(tag: "cover_photo", attrs: ["op": "delete", "id": coverPhotoID])
					])
				)
			])
		))
	}

	public func removeCoverPhoto(id coverPhotoID: String, requestID: String? = nil) async throws {
		try await removeBusinessCoverPhoto(id: coverPhotoID, requestID: requestID)
	}

	public func businessCatalog(
		for jid: String,
		limit: Int = 10,
		cursor: String? = nil,
		requestID: String? = nil
	) async throws -> BusinessCatalog {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		var queryNodes = [
			BinaryNode(tag: "limit", content: .string(String(limit))),
			BinaryNode(tag: "width", content: .string("100")),
			BinaryNode(tag: "height", content: .string("100"))
		]
		if let cursor {
			queryNodes.append(BinaryNode(tag: "after", content: .string(cursor)))
		}

		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "get",
				"xmlns": "w:biz:catalog"
			],
			content: .nodes([
				BinaryNode(
					tag: "product_catalog",
					attrs: [
						"jid": JID(jid)?.normalizedUser ?? jid,
						"allow_shop_source": "true"
					],
					content: .nodes(queryNodes)
				)
			])
		))

		guard let catalog = result.firstChild(named: "product_catalog") else {
			return BusinessCatalog(products: [], nextPageCursor: nil)
		}

		return BusinessCatalog(
			products: catalog.children(named: "product").compactMap(Self.parseBusinessProduct(_:)),
			nextPageCursor: catalog.firstChild(named: "paging")?.childString(named: "after")
		)
	}

	public func getCatalog(
		for jid: String,
		limit: Int = 10,
		cursor: String? = nil,
		requestID: String? = nil
	) async throws -> BusinessCatalog {
		try await businessCatalog(for: jid, limit: limit, cursor: cursor, requestID: requestID)
	}

	public func businessCollections(
		for jid: String,
		limit: Int = 51,
		requestID: String? = nil
	) async throws -> BusinessCatalogCollections {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "get",
				"xmlns": "w:biz:catalog",
				"smax_id": "35"
			],
			content: .nodes([
				BinaryNode(
					tag: "collections",
					attrs: ["biz_jid": JID(jid)?.normalizedUser ?? jid],
					content: .nodes([
						BinaryNode(tag: "collection_limit", content: .string(String(limit))),
						BinaryNode(tag: "item_limit", content: .string(String(limit))),
						BinaryNode(tag: "width", content: .string("100")),
						BinaryNode(tag: "height", content: .string("100"))
					])
				)
			])
		))

		let collections = result.firstChild(named: "collections")?.children(named: "collection").compactMap { collection in
			Self.parseBusinessCollection(collection)
		} ?? []
		return BusinessCatalogCollections(collections: collections)
	}

	public func getCollections(
		for jid: String,
		limit: Int = 51,
		requestID: String? = nil
	) async throws -> BusinessCatalogCollections {
		try await businessCollections(for: jid, limit: limit, requestID: requestID)
	}

	public func businessOrderDetails(
		orderID: String,
		tokenBase64: String,
		requestID: String? = nil
	) async throws -> BusinessOrderDetails {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "get",
				"xmlns": "fb:thrift_iq",
				"smax_id": "5"
			],
			content: .nodes([
				BinaryNode(
					tag: "order",
					attrs: ["op": "get", "id": orderID],
					content: .nodes([
						BinaryNode(tag: "image_dimensions", content: .nodes([
							BinaryNode(tag: "width", content: .string("100")),
							BinaryNode(tag: "height", content: .string("100"))
						])),
						BinaryNode(tag: "token", content: .string(tokenBase64))
					])
				)
			])
		))

		return Self.parseBusinessOrderDetails(from: result)
	}

	public func getOrderDetails(
		orderID: String,
		tokenBase64: String,
		requestID: String? = nil
	) async throws -> BusinessOrderDetails {
		try await businessOrderDetails(orderID: orderID, tokenBase64: tokenBase64, requestID: requestID)
	}

	public func businessProductDelete(
		ids productIDs: [String],
		requestID: String? = nil
	) async throws -> BusinessProductDeleteResult {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "w:biz:catalog"
			],
			content: .nodes([
				BinaryNode(
					tag: "product_catalog_delete",
					attrs: ["v": "1"],
					content: .nodes(productIDs.map { productID in
						BinaryNode(tag: "product", content: .nodes([
							BinaryNode(tag: "id", content: .string(productID))
						]))
					})
				)
			])
		))

		let deleted = result
			.firstChild(named: "product_catalog_delete")?
			.attrs["deleted_count"]
			.flatMap(Int.init) ?? 0
		return BusinessProductDeleteResult(deleted: deleted)
	}

	public func productDelete(ids productIDs: [String], requestID: String? = nil) async throws -> BusinessProductDeleteResult {
		try await businessProductDelete(ids: productIDs, requestID: requestID)
	}

	public func businessProductCreate(
		_ product: BusinessProductCreate,
		requestID: String? = nil
	) async throws -> BusinessProduct {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "w:biz:catalog"
			],
			content: .nodes([
				BinaryNode(
					tag: "product_catalog_add",
					attrs: ["v": "1"],
					content: .nodes([
						Self.makeBusinessProductCreateNode(product),
						BinaryNode(tag: "width", content: .string("100")),
						BinaryNode(tag: "height", content: .string("100"))
					])
				)
			])
		))

		guard
			let productNode = result.firstChild(named: "product_catalog_add")?.firstChild(named: "product"),
			let createdProduct = Self.parseBusinessProduct(productNode)
		else {
			throw WhatsAppClientError.missingBusinessProductResponse
		}

		return createdProduct
	}

	public func productCreate(_ product: BusinessProductCreate, requestID: String? = nil) async throws -> BusinessProduct {
		try await businessProductCreate(product, requestID: requestID)
	}

	public func businessProductUpdate(
		id productID: String,
		update: BusinessProductUpdate,
		requestID: String? = nil
	) async throws -> BusinessProduct {
		let id = try requestID ?? messageIDGenerator.generateV2(userID: authenticationState?.credentials.me?.id)
		let result = try await query(BinaryNode(
			tag: "iq",
			attrs: [
				"id": id,
				"to": "@s.whatsapp.net",
				"type": "set",
				"xmlns": "w:biz:catalog"
			],
			content: .nodes([
				BinaryNode(
					tag: "product_catalog_edit",
					attrs: ["v": "1"],
					content: .nodes([
						Self.makeBusinessProductUpdateNode(id: productID, update: update),
						BinaryNode(tag: "width", content: .string("100")),
						BinaryNode(tag: "height", content: .string("100"))
					])
				)
			])
		))

		guard
			let productNode = result.firstChild(named: "product_catalog_edit")?.firstChild(named: "product"),
			let updatedProduct = Self.parseBusinessProduct(productNode)
		else {
			throw WhatsAppClientError.missingBusinessProductResponse
		}

		return updatedProduct
	}

	public func productUpdate(
		id productID: String,
		update: BusinessProductUpdate,
		requestID: String? = nil
	) async throws -> BusinessProduct {
		try await businessProductUpdate(id: productID, update: update, requestID: requestID)
	}

	private static func makeBusinessProductCreateNode(_ product: BusinessProductCreate) -> BinaryNode {
		var attrs = BinaryNodeAttributes([("is_hidden", product.isHidden ? "true" : "false")])
		var nodes = [
			BinaryNode(tag: "name", content: .string(product.name)),
			BinaryNode(tag: "description", content: .string(product.description))
		]

		if let retailerID = product.retailerID {
			nodes.append(BinaryNode(tag: "retailer_id", content: .string(retailerID)))
		}

		if let media = Self.makeBusinessProductMediaNode(product.imageURLs) {
			nodes.append(media)
		}
		nodes.append(BinaryNode(tag: "price", content: .string(String(product.price))))
		nodes.append(BinaryNode(tag: "currency", content: .string(product.currency)))
		if let originCountryCode = product.originCountryCode {
			nodes.append(BinaryNode(tag: "compliance_info", content: .nodes([
				BinaryNode(tag: "country_code_origin", content: .string(originCountryCode))
			])))
		} else {
			attrs = BinaryNodeAttributes([
				("is_hidden", product.isHidden ? "true" : "false"),
				("compliance_category", "COUNTRY_ORIGIN_EXEMPT")
			])
		}

		return BinaryNode(tag: "product", attrs: attrs, content: .nodes(nodes))
	}

	private static func makeBusinessProductUpdateNode(id productID: String, update: BusinessProductUpdate) -> BinaryNode {
		var nodes = [BinaryNode(tag: "id", content: .string(productID))]
		if let name = update.name {
			nodes.append(BinaryNode(tag: "name", content: .string(name)))
		}

		if let description = update.description {
			nodes.append(BinaryNode(tag: "description", content: .string(description)))
		}

		if let retailerID = update.retailerID {
			nodes.append(BinaryNode(tag: "retailer_id", content: .string(retailerID)))
		}

		if let media = Self.makeBusinessProductMediaNode(update.imageURLs) {
			nodes.append(media)
		}

		if let price = update.price {
			nodes.append(BinaryNode(tag: "price", content: .string(String(price))))
		}

		if let currency = update.currency {
			nodes.append(BinaryNode(tag: "currency", content: .string(currency)))
		}

		var attrs = BinaryNodeAttributes()
		if let isHidden = update.isHidden {
			attrs = BinaryNodeAttributes([("is_hidden", isHidden ? "true" : "false")])
		}

		return BinaryNode(tag: "product", attrs: attrs, content: .nodes(nodes))
	}

	private static func makeBusinessProductMediaNode(_ urls: [String]) -> BinaryNode? {
		guard !urls.isEmpty else {
			return nil
		}

		return BinaryNode(
			tag: "media",
			content: .nodes(urls.map { url in
				BinaryNode(tag: "image", content: .nodes([
					BinaryNode(tag: "url", content: .string(url))
				]))
			})
		)
	}

	private static func parseBusinessProduct(_ node: BinaryNode) -> BusinessProduct? {
		guard
			let id = node.childString(named: "id"),
			let name = node.childString(named: "name"),
			let description = node.childString(named: "description"),
			let priceValue = node.childString(named: "price"),
			let price = Int(priceValue),
			let currency = node.childString(named: "currency"),
			let image = node.firstChild(named: "media")?.firstChild(named: "image"),
			let requested = image.childString(named: "request_image_url"),
			let original = image.childString(named: "original_image_url")
		else {
			return nil
		}

		return BusinessProduct(
			id: id,
			name: name,
			retailerID: node.childString(named: "retailer_id"),
			url: node.childString(named: "url"),
			description: description,
			price: price,
			currency: currency,
			isHidden: node.attrs["is_hidden"] == "true",
			imageURLs: BusinessProductImageURLs(requested: requested, original: original),
			reviewStatus: ["whatsapp": node.firstChild(named: "status_info")?.childString(named: "status") ?? ""],
			availability: "in stock"
		)
	}

	private static func parseBusinessCollection(_ node: BinaryNode) -> BusinessCatalogCollection? {
		guard let id = node.childString(named: "id"), let name = node.childString(named: "name") else {
			return nil
		}

		return BusinessCatalogCollection(
			id: id,
			name: name,
			products: node.children(named: "product").compactMap(Self.parseBusinessProduct(_:)),
			status: parseBusinessCatalogStatus(from: node)
		)
	}

	private static func parseBusinessCatalogStatus(from node: BinaryNode) -> BusinessCatalogStatus {
		let statusNode = node.firstChild(named: "status_info")
		return BusinessCatalogStatus(
			status: statusNode?.childString(named: "status") ?? "",
			canAppeal: statusNode?.childString(named: "can_appeal") == "true"
		)
	}

	private static func parseBusinessOrderDetails(from node: BinaryNode) -> BusinessOrderDetails {
		let order = node.firstChild(named: "order")
		let priceNode = order?.firstChild(named: "price")
		let total = priceNode?.childString(named: "total").flatMap(Int.init) ?? 0
		let currency = priceNode?.childString(named: "currency") ?? ""
		let products = order?.children(named: "product").compactMap(parseBusinessOrderProduct(_:)) ?? []
		return BusinessOrderDetails(price: BusinessOrderPrice(currency: currency, total: total), products: products)
	}

	private static func parseBusinessOrderProduct(_ node: BinaryNode) -> BusinessOrderProduct? {
		guard
			let id = node.childString(named: "id"),
			let name = node.childString(named: "name"),
			let imageURL = node.firstChild(named: "image")?.childString(named: "url"),
			let priceValue = node.childString(named: "price"),
			let price = Int(priceValue),
			let currency = node.childString(named: "currency"),
			let quantityValue = node.childString(named: "quantity"),
			let quantity = Int(quantityValue)
		else {
			return nil
		}

		return BusinessOrderProduct(
			id: id,
			imageURL: imageURL,
			name: name,
			quantity: quantity,
			currency: currency,
			price: price
		)
	}
}
