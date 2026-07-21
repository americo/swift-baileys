import Foundation
import Testing
@testable import WhatsAppWeb

@Suite("Raw media upload data writer")
struct RawMediaUploadDataTests {
	@Test("writes data source to media typed file and returns hash metadata")
	func writesDataSourceToMediaTypedFileAndReturnsHashMetadata() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let data = Data([1, 2, 3, 4])

		let result = try RawMediaUploadDataWriter.write(
			from: .data(data),
			mediaType: .image,
			directory: directory,
			fileName: "image3EB0TEST"
		)

		#expect(result.fileURL.lastPathComponent == "image3EB0TEST")
		#expect(try Data(contentsOf: result.fileURL) == data)
		#expect(result.fileLength == 4)
		#expect(result.fileSHA256 == (try hexData("9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a")))
	}

	@Test("copies file source and hashes streamed bytes")
	func copiesFileSourceAndHashesStreamedBytes() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let sourceURL = directory.appendingPathComponent("source.bin")
		let data = Data("stream me".utf8)
		try data.write(to: sourceURL)

		let result = try RawMediaUploadDataWriter.write(
			from: .file(sourceURL),
			mediaType: .video,
			directory: directory,
			fileName: "video3EB0TEST"
		)

		#expect(result.fileURL.lastPathComponent == "video3EB0TEST")
		#expect(try Data(contentsOf: result.fileURL) == data)
		#expect(result.fileLength == data.count)
		#expect(result.fileSHA256 == (try hexData("072e61241ebf17f37fd33dbe578b6819619f17cd56144512a070999cfb4bdd40")))
	}

	@Test("supports empty data source like Baileys raw media writer")
	func supportsEmptyDataSourceLikeBaileysRawMediaWriter() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let result = try RawMediaUploadDataWriter.write(
			from: .data(Data()),
			mediaType: .document,
			directory: directory,
			fileName: "document3EB0TEST"
		)

		#expect(try Data(contentsOf: result.fileURL).isEmpty)
		#expect(result.fileLength == 0)
		#expect(result.fileSHA256 == (try hexData("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")))
	}

	@Test("removes partial destination when file source cannot be opened")
	func removesPartialDestinationWhenFileSourceCannotBeOpened() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let missingSourceURL = directory.appendingPathComponent("missing.bin")
		let destinationURL = directory.appendingPathComponent("audio3EB0TEST")

		#expect(throws: (any Error).self) {
			_ = try RawMediaUploadDataWriter.write(
				from: .file(missingSourceURL),
				mediaType: .audio,
				directory: directory,
				fileName: "audio3EB0TEST"
			)
		}
		#expect(!FileManager.default.fileExists(atPath: destinationURL.path))
	}
}

private func makeTemporaryDirectory() throws -> URL {
	let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	return directory
}
