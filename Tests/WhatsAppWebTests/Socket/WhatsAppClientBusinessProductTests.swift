import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("WhatsApp client business products")
struct WhatsAppClientBusinessProductTests {
	@Test("deletes business catalog products")
	func deletesBusinessCatalogProducts() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessProductDelete(ids: ["prod-1", "prod-2"], requestID: "product-delete-1")
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "product-delete-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:biz:catalog")
		let delete = try #require(request.firstChild(named: "product_catalog_delete"))
		#expect(delete.attrs["v"] == "1")
		#expect(delete.children(named: "product").map { $0.childString(named: "id") } == ["prod-1", "prod-2"])

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "product-delete-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "product_catalog_delete", attrs: ["deleted_count": "2"])
			])
		))

		let result = try await task.value
		#expect(result.deleted == 2)
	}

	@Test("creates business catalog product")
	func createsBusinessCatalogProduct() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessProductCreate(
				BusinessProductCreate(
					name: "Coffee",
					retailerID: "sku-1",
					description: "Ground coffee",
					price: 1500,
					currency: "MZN",
					isHidden: false,
					originCountryCode: "MZ",
					imageURLs: ["https://mmg.whatsapp.net/uploaded.jpg"]
				),
				requestID: "product-create-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "product-create-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:biz:catalog")
		let add = try #require(request.firstChild(named: "product_catalog_add"))
		#expect(add.attrs["v"] == "1")
		#expect(add.childString(named: "width") == "100")
		#expect(add.childString(named: "height") == "100")
		let product = try #require(add.firstChild(named: "product"))
		#expect(product.attrs["is_hidden"] == "false")
		#expect(product.childString(named: "name") == "Coffee")
		#expect(product.childString(named: "retailer_id") == "sku-1")
		#expect(product.childString(named: "description") == "Ground coffee")
		#expect(product.childString(named: "price") == "1500")
		#expect(product.childString(named: "currency") == "MZN")
		#expect(product.firstChild(named: "media")?.firstChild(named: "image")?.childString(named: "url") == "https://mmg.whatsapp.net/uploaded.jpg")
		#expect(product.firstChild(named: "compliance_info")?.childString(named: "country_code_origin") == "MZ")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "product-create-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "product_catalog_add", content: .nodes([
					BinaryNode(tag: "product", attrs: ["is_hidden": "false"], content: .nodes([
						BinaryNode(tag: "id", content: .string("prod-1")),
						BinaryNode(tag: "name", content: .string("Coffee")),
						BinaryNode(tag: "retailer_id", content: .string("sku-1")),
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
					]))
				]))
			])
		))

		let result = try await task.value
		#expect(result.id == "prod-1")
		#expect(result.name == "Coffee")
		#expect(result.imageURLs.original == "https://mmg.whatsapp.net/original.jpg")
	}

	@Test("updates business catalog product")
	func updatesBusinessCatalogProduct() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let task = Task {
			try await client.businessProductUpdate(
				id: "prod-1",
				update: BusinessProductUpdate(
					name: "Coffee beans",
					retailerID: "sku-1b",
					description: "Whole beans",
					price: 1800,
					currency: "MZN",
					isHidden: true,
					imageURLs: ["https://mmg.whatsapp.net/updated.jpg"]
				),
				requestID: "product-update-1"
			)
		}
		let request = try await transport.waitForSentNode()
		#expect(request.attrs["id"] == "product-update-1")
		#expect(request.attrs["to"] == "@s.whatsapp.net")
		#expect(request.attrs["type"] == "set")
		#expect(request.attrs["xmlns"] == "w:biz:catalog")
		let edit = try #require(request.firstChild(named: "product_catalog_edit"))
		#expect(edit.attrs["v"] == "1")
		#expect(edit.childString(named: "width") == "100")
		#expect(edit.childString(named: "height") == "100")
		let product = try #require(edit.firstChild(named: "product"))
		#expect(product.attrs["is_hidden"] == "true")
		#expect(product.childString(named: "id") == "prod-1")
		#expect(product.childString(named: "name") == "Coffee beans")
		#expect(product.childString(named: "retailer_id") == "sku-1b")
		#expect(product.childString(named: "description") == "Whole beans")
		#expect(product.childString(named: "price") == "1800")
		#expect(product.childString(named: "currency") == "MZN")
		#expect(product.firstChild(named: "media")?.firstChild(named: "image")?.childString(named: "url") == "https://mmg.whatsapp.net/updated.jpg")

		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "product-update-1", "type": "result"],
			content: .nodes([
				BinaryNode(tag: "product_catalog_edit", content: .nodes([
					BinaryNode(tag: "product", attrs: ["is_hidden": "true"], content: .nodes([
						BinaryNode(tag: "id", content: .string("prod-1")),
						BinaryNode(tag: "name", content: .string("Coffee beans")),
						BinaryNode(tag: "retailer_id", content: .string("sku-1b")),
						BinaryNode(tag: "description", content: .string("Whole beans")),
						BinaryNode(tag: "price", content: .string("1800")),
						BinaryNode(tag: "currency", content: .string("MZN")),
						BinaryNode(tag: "media", content: .nodes([
							BinaryNode(tag: "image", content: .nodes([
								BinaryNode(tag: "request_image_url", content: .string("https://mmg.whatsapp.net/update-request.jpg")),
								BinaryNode(tag: "original_image_url", content: .string("https://mmg.whatsapp.net/update-original.jpg"))
							]))
						])),
						BinaryNode(tag: "status_info", content: .nodes([
							BinaryNode(tag: "status", content: .string("approved"))
						]))
					]))
				]))
			])
		))

		let result = try await task.value
		#expect(result.id == "prod-1")
		#expect(result.name == "Coffee beans")
		#expect(result.isHidden)
		#expect(result.imageURLs.requested == "https://mmg.whatsapp.net/update-request.jpg")
	}

	@Test("Baileys product aliases send catalog mutations")
	func baileysProductAliasesSendCatalogMutations() async throws {
		let transport = MockBusinessWebSocketTransport()
		let client = WhatsAppClient(transportFactory: { _ in transport })
		try await client.connect()

		let deleteTask = Task {
			try await client.productDelete(ids: ["prod-1"], requestID: "product-delete-alias")
		}
		let deleteRequest = try await transport.waitForSentNode()
		#expect(deleteRequest.firstChild(named: "product_catalog_delete")?.children(named: "product").map { $0.childString(named: "id") } == ["prod-1"])
		await transport.enqueueInbound(BinaryNode(
			tag: "iq",
			attrs: ["id": "product-delete-alias", "type": "result"],
			content: .nodes([BinaryNode(tag: "product_catalog_delete", attrs: ["deleted_count": "1"])])
		))
		#expect(try await deleteTask.value.deleted == 1)

		let createTask = Task {
			try await client.productCreate(
				BusinessProductCreate(
					name: "Coffee",
					description: "Ground coffee",
					price: 1500,
					currency: "MZN",
					imageURLs: []
				),
				requestID: "product-create-alias"
			)
		}
		let createRequest = try await transport.waitForSentNode(at: 1)
		#expect(createRequest.firstChild(named: "product_catalog_add")?.firstChild(named: "product")?.childString(named: "name") == "Coffee")
		await transport.enqueueInbound(productMutationResponse(
			id: "product-create-alias",
			parentTag: "product_catalog_add",
			productName: "Coffee"
		))
		#expect(try await createTask.value.name == "Coffee")

		let updateTask = Task {
			try await client.productUpdate(
				id: "prod-1",
				update: BusinessProductUpdate(name: "Coffee beans"),
				requestID: "product-update-alias"
			)
		}
		let updateRequest = try await transport.waitForSentNode(at: 2)
		let updateProduct = try #require(updateRequest.firstChild(named: "product_catalog_edit")?.firstChild(named: "product"))
		#expect(updateProduct.childString(named: "id") == "prod-1")
		#expect(updateProduct.childString(named: "name") == "Coffee beans")
		await transport.enqueueInbound(productMutationResponse(
			id: "product-update-alias",
			parentTag: "product_catalog_edit",
			productName: "Coffee beans"
		))
		#expect(try await updateTask.value.name == "Coffee beans")
	}
}

private func productMutationResponse(id: String, parentTag: String, productName: String) -> BinaryNode {
	BinaryNode(
		tag: "iq",
		attrs: ["id": id, "type": "result"],
		content: .nodes([
			BinaryNode(tag: parentTag, content: .nodes([
				BinaryNode(tag: "product", attrs: ["is_hidden": "false"], content: .nodes([
					BinaryNode(tag: "id", content: .string("prod-1")),
					BinaryNode(tag: "name", content: .string(productName)),
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
				]))
			]))
		])
	)
}
