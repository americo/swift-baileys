enum ForwardProductMessageMapper {
	static func message(from content: ReceivedProductContent) -> Proto_Message {
		let productMessage = product(from: content)

		var message = Proto_Message()
		message.productMessage = productMessage
		return message
	}

	static func product(from content: ReceivedProductContent) -> Proto_Message.ProductMessage {
		var productMessage = Proto_Message.ProductMessage()
		if let product = content.product {
			productMessage.product = productSnapshot(from: product)
		}
		if let businessOwnerJID = content.businessOwnerJID {
			productMessage.businessOwnerJid = businessOwnerJID
		}
		if let catalog = content.catalog {
			productMessage.catalog = productCatalog(from: catalog)
		}
		if let body = content.body {
			productMessage.body = body
		}
		if let footer = content.footer {
			productMessage.footer = footer
		}
		return productMessage
	}

	private static func productSnapshot(
		from content: ReceivedProductSnapshotContent
	) -> Proto_Message.ProductMessage.ProductSnapshot {
		var snapshot = Proto_Message.ProductMessage.ProductSnapshot()
		if let image = content.image {
			snapshot.productImage = productImage(from: image)
		}
		if let productID = content.productID {
			snapshot.productID = productID
		}
		if let title = content.title {
			snapshot.title = title
		}
		if let description = content.description {
			snapshot.description_p = description
		}
		if let currencyCode = content.currencyCode {
			snapshot.currencyCode = currencyCode
		}
		if let priceAmount1000 = content.priceAmount1000 {
			snapshot.priceAmount1000 = priceAmount1000
		}
		if let retailerID = content.retailerID {
			snapshot.retailerID = retailerID
		}
		if let url = content.url {
			snapshot.url = url
		}
		if let productImageCount = content.productImageCount {
			snapshot.productImageCount = productImageCount
		}
		if let firstImageID = content.firstImageID {
			snapshot.firstImageID = firstImageID
		}
		if let salePriceAmount1000 = content.salePriceAmount1000 {
			snapshot.salePriceAmount1000 = salePriceAmount1000
		}
		if let signedURL = content.signedURL {
			snapshot.signedURL = signedURL
		}
		return snapshot
	}

	private static func productCatalog(
		from content: ReceivedProductCatalogContent
	) -> Proto_Message.ProductMessage.CatalogSnapshot {
		var catalog = Proto_Message.ProductMessage.CatalogSnapshot()
		if let image = content.image {
			catalog.catalogImage = productImage(from: image)
		}
		if let title = content.title {
			catalog.title = title
		}
		if let description = content.description {
			catalog.description_p = description
		}
		return catalog
	}

	private static func productImage(from content: ReceivedProductImageContent) -> Proto_Message.ImageMessage {
		var image = Proto_Message.ImageMessage()
		image.url = content.url
		image.directPath = content.directPath
		image.mediaKey = content.mediaKey
		image.fileEncSha256 = content.fileEncSHA256
		image.fileSha256 = content.fileSHA256
		image.fileLength = content.fileLength
		image.mediaKeyTimestamp = content.mediaKeyTimestamp
		image.mimetype = content.mimetype
		if let caption = content.caption {
			image.caption = caption
		}
		if let jpegThumbnail = content.jpegThumbnail {
			image.jpegThumbnail = jpegThumbnail
		}
		return image
	}
}
