import CryptoKit
import Foundation

public enum RawMediaUploadSource: Equatable, Sendable {
	case data(Data)
	case file(URL)
}

public struct RawMediaUploadData: Equatable, Sendable {
	public let fileURL: URL
	public let fileSHA256: Data
	public let fileLength: Int

	public init(fileURL: URL, fileSHA256: Data, fileLength: Int) {
		self.fileURL = fileURL
		self.fileSHA256 = fileSHA256
		self.fileLength = fileLength
	}
}

public enum RawMediaUploadDataWriter {
	public static func write(
		from source: RawMediaUploadSource,
		mediaType: MediaType,
		directory: URL = FileManager.default.temporaryDirectory,
		fileName: String? = nil
	) throws -> RawMediaUploadData {
		let name: String
		if let fileName {
			name = fileName
		} else {
			name = "\(mediaType.rawValue)\(try MessageIDGenerator().generateV2())"
		}
		let fileURL = directory.appendingPathComponent(name, isDirectory: false)
		do {
			switch source {
			case .data(let data):
				try data.write(to: fileURL, options: .atomic)
				return RawMediaUploadData(
					fileURL: fileURL,
					fileSHA256: Data(SHA256.hash(data: data)),
					fileLength: data.count
				)
			case .file(let sourceURL):
				return try copyAndHashFile(from: sourceURL, to: fileURL)
			}
		} catch {
			try? FileManager.default.removeItem(at: fileURL)
			throw error
		}
	}
}

private extension RawMediaUploadDataWriter {
	static func copyAndHashFile(from sourceURL: URL, to fileURL: URL) throws -> RawMediaUploadData {
		FileManager.default.createFile(atPath: fileURL.path, contents: nil)
		let input = try FileHandle(forReadingFrom: sourceURL)
		let output = try FileHandle(forWritingTo: fileURL)
		defer {
			try? input.close()
			try? output.close()
		}

		var hasher = SHA256()
		var length = 0
		while true {
			let chunk = try input.read(upToCount: 64 * 1024) ?? Data()
			if chunk.isEmpty {
				break
			}
			try output.write(contentsOf: chunk)
			hasher.update(data: chunk)
			length += chunk.count
		}

		return RawMediaUploadData(
			fileURL: fileURL,
			fileSHA256: Data(hasher.finalize()),
			fileLength: length
		)
	}
}
