extension ReceivedMessageContentParser {
	static func productContent(_ productMessage: Proto_Message.ProductMessage) -> ReceivedProductContent {
		ReceivedProductContent(
			product: productMessage.hasProduct ? productSnapshot(productMessage.product) : nil,
			businessOwnerJID: productMessage.hasBusinessOwnerJid ? productMessage.businessOwnerJid : nil,
			catalog: productMessage.hasCatalog ? productCatalog(productMessage.catalog) : nil,
			body: productMessage.hasBody ? productMessage.body : nil,
			footer: productMessage.hasFooter ? productMessage.footer : nil
		)
	}

	static func productSnapshot(
		_ product: Proto_Message.ProductMessage.ProductSnapshot
	) -> ReceivedProductSnapshotContent {
		ReceivedProductSnapshotContent(
			image: product.hasProductImage ? productImage(product.productImage) : nil,
			productID: product.hasProductID ? product.productID : nil,
			title: product.hasTitle ? product.title : nil,
			description: product.hasDescription_p ? product.description_p : nil,
			currencyCode: product.hasCurrencyCode ? product.currencyCode : nil,
			priceAmount1000: product.hasPriceAmount1000 ? product.priceAmount1000 : nil,
			retailerID: product.hasRetailerID ? product.retailerID : nil,
			url: product.hasURL ? product.url : nil,
			productImageCount: product.hasProductImageCount ? product.productImageCount : nil,
			firstImageID: product.hasFirstImageID ? product.firstImageID : nil,
			salePriceAmount1000: product.hasSalePriceAmount1000 ? product.salePriceAmount1000 : nil,
			signedURL: product.hasSignedURL ? product.signedURL : nil
		)
	}

	static func productCatalog(
		_ catalog: Proto_Message.ProductMessage.CatalogSnapshot
	) -> ReceivedProductCatalogContent {
		ReceivedProductCatalogContent(
			image: catalog.hasCatalogImage ? productImage(catalog.catalogImage) : nil,
			title: catalog.hasTitle ? catalog.title : nil,
			description: catalog.hasDescription_p ? catalog.description_p : nil
		)
	}

	static func productImage(_ image: Proto_Message.ImageMessage) -> ReceivedProductImageContent {
		ReceivedProductImageContent(
			url: image.url,
			directPath: image.directPath,
			mediaKey: image.mediaKey,
			fileEncSHA256: image.fileEncSha256,
			fileSHA256: image.fileSha256,
			fileLength: image.fileLength,
			mediaKeyTimestamp: image.mediaKeyTimestamp,
			mimetype: image.mimetype,
			caption: image.hasCaption ? image.caption : nil,
			jpegThumbnail: image.hasJpegThumbnail ? image.jpegThumbnail : nil
		)
	}

	static func orderContent(_ order: Proto_Message.OrderMessage) -> ReceivedOrderContent {
		ReceivedOrderContent(
			orderID: order.hasOrderID ? order.orderID : nil,
			thumbnail: order.hasThumbnail ? order.thumbnail : nil,
			itemCount: order.hasItemCount ? order.itemCount : nil,
			status: order.hasStatus ? orderStatus(order.status) : nil,
			surface: order.hasSurface ? orderSurface(order.surface) : nil,
			message: order.hasMessage ? order.message : nil,
			orderTitle: order.hasOrderTitle ? order.orderTitle : nil,
			sellerJID: order.hasSellerJid ? order.sellerJid : nil,
			token: order.hasToken ? order.token : nil,
			totalAmount1000: order.hasTotalAmount1000 ? order.totalAmount1000 : nil,
			totalCurrencyCode: order.hasTotalCurrencyCode ? order.totalCurrencyCode : nil,
			messageVersion: order.hasMessageVersion ? order.messageVersion : nil,
			orderRequestMessageID: order.hasOrderRequestMessageID ? messageKey(order.orderRequestMessageID) : nil,
			catalogType: order.hasCatalogType ? order.catalogType : nil
		)
	}

	static func orderStatus(_ status: Proto_Message.OrderMessage.OrderStatus) -> ReceivedOrderStatus {
		switch status {
		case .unknown:
			.unknown
		case .inquiry:
			.inquiry
		case .accepted:
			.accepted
		case .declined:
			.declined
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	static func orderSurface(_ surface: Proto_Message.OrderMessage.OrderSurface) -> ReceivedOrderSurface {
		switch surface {
		case .unknown:
			.unknown
		case .catalog:
			.catalog
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
