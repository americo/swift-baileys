import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ProfilePictureDimensions: Equatable, Sendable {
	public let width: Int
	public let height: Int

	public init(width: Int = 640, height: Int = 640) {
		self.width = width
		self.height = height
	}
}

public enum ProfilePictureImageProcessorError: Error, Equatable, Sendable {
	case invalidImage
	case invalidDimensions
	case renderFailed
	case encodeFailed
}

public enum ProfilePictureImageProcessor {
	public static func makeJPEGData(
		from imageData: Data,
		dimensions: ProfilePictureDimensions = ProfilePictureDimensions(),
		compressionQuality: Double = 0.5
	) throws -> Data {
		guard dimensions.width > 0, dimensions.height > 0 else {
			throw ProfilePictureImageProcessorError.invalidDimensions
		}

		guard
			let source = CGImageSourceCreateWithData(imageData as CFData, nil),
			let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
		else {
			throw ProfilePictureImageProcessorError.invalidImage
		}

		let croppedImage = image.cropping(to: centeredSquareCropRect(for: image)) ?? image
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		guard let context = CGContext(
			data: nil,
			width: dimensions.width,
			height: dimensions.height,
			bitsPerComponent: 8,
			bytesPerRow: dimensions.width * 4,
			space: colorSpace,
			bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
		) else {
			throw ProfilePictureImageProcessorError.renderFailed
		}

		context.interpolationQuality = .high
		context.draw(
			croppedImage,
			in: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
		)
		guard let resizedImage = context.makeImage() else {
			throw ProfilePictureImageProcessorError.renderFailed
		}

		let output = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(
			output,
			UTType.jpeg.identifier as CFString,
			1,
			nil
		) else {
			throw ProfilePictureImageProcessorError.encodeFailed
		}

		CGImageDestinationAddImage(
			destination,
			resizedImage,
			[kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
		)
		guard CGImageDestinationFinalize(destination) else {
			throw ProfilePictureImageProcessorError.encodeFailed
		}

		return output as Data
	}
}

private func centeredSquareCropRect(for image: CGImage) -> CGRect {
	let side = min(image.width, image.height)
	return CGRect(
		x: (image.width - side) / 2,
		y: (image.height - side) / 2,
		width: side,
		height: side
	)
}
