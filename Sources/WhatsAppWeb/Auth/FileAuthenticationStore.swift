import Foundation

public actor FileAuthenticationStore {
	public nonisolated let directory: URL
	public nonisolated let keys: FileSignalKeyStore

	private let encoder: JSONEncoder
	private let decoder: JSONDecoder

	public init(directory: URL) {
		self.directory = directory
		self.keys = FileSignalKeyStore(directory: directory)
		self.encoder = JSONEncoder()
		self.decoder = JSONDecoder()
	}

	public func loadCredentials() async throws -> AuthenticationCredentials? {
		let url = directory.appendingPathComponent("creds.json")
		guard FileManager.default.fileExists(atPath: url.path) else {
			return nil
		}

		let data = try Data(contentsOf: url)
		return try BaileysBufferJSON.decode(AuthenticationCredentials.self, from: data, decoder: decoder)
	}

	public func saveCredentials(_ credentials: AuthenticationCredentials) async throws {
		try ensureDirectoryExists()
		let url = directory.appendingPathComponent("creds.json")
		let data = try encoder.encode(credentials)
		try data.write(to: url, options: .atomic)
		try setSecureFilePermissions(at: url)
	}

	public func clear() async throws {
		try await keys.clear()
		try? FileManager.default.removeItem(at: directory.appendingPathComponent("creds.json"))
	}

	private func ensureDirectoryExists() throws {
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
			if !isDirectory.boolValue {
				throw FileAuthenticationStoreError.pathIsNotDirectory(directory)
			}
		} else {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		try setSecureDirectoryPermissions(at: directory)
	}
}

public actor FileSignalKeyStore: SignalKeyStore {
	public nonisolated let directory: URL

	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	public init(directory: URL) {
		self.directory = directory
	}

	public func get(_ category: SignalKeyCategory, ids: [String]) async throws -> [String: Data] {
		var result: [String: Data] = [:]

		for id in ids {
			let url = existingFileURL(category: category, id: id)
			if FileManager.default.fileExists(atPath: url.path) {
				let data = try Data(contentsOf: url)
				result[id] = try decoder.decode(Data.self, from: data)
			}
		}

		return result
	}

	public func set(_ values: [SignalKeyCategory: [String: Data?]]) async throws {
		try ensureDirectoryExists()

		for (category, updates) in values {
			for (id, value) in updates {
				let url = fileURL(category: category, id: id)
				let legacyURL = legacyFileURL(category: category, id: id)

				if let value {
					let data = try encoder.encode(value)
					try data.write(to: url, options: .atomic)
					try setSecureFilePermissions(at: url)
					if legacyURL != url {
						try? FileManager.default.removeItem(at: legacyURL)
					}
				} else {
					try? FileManager.default.removeItem(at: url)
					if legacyURL != url {
						try? FileManager.default.removeItem(at: legacyURL)
					}
				}
			}
		}
	}

	public func clear() async throws {
		guard FileManager.default.fileExists(atPath: directory.path) else {
			return
		}

		for category in SignalKeyCategory.allCases {
			let prefix = "\(category.rawValue)-"
			for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
				if url.lastPathComponent.hasPrefix(prefix) {
					try FileManager.default.removeItem(at: url)
				}
			}
		}
	}

	private func fileURL(category: SignalKeyCategory, id: String) -> URL {
		directory.appendingPathComponent("\(category.rawValue)-\(encodedFileName(id)).json")
	}

	private func legacyFileURL(category: SignalKeyCategory, id: String) -> URL {
		directory.appendingPathComponent("\(category.rawValue)-\(legacySanitizeFileName(id)).json")
	}

	private func existingFileURL(category: SignalKeyCategory, id: String) -> URL {
		let url = fileURL(category: category, id: id)
		if FileManager.default.fileExists(atPath: url.path) {
			return url
		}

		return legacyFileURL(category: category, id: id)
	}

	private func encodedFileName(_ value: String) -> String {
		Data(value.utf8)
			.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}

	private func legacySanitizeFileName(_ value: String) -> String {
		value.replacingOccurrences(of: "/", with: "__").replacingOccurrences(of: ":", with: "-")
	}

	private func ensureDirectoryExists() throws {
		var isDirectory: ObjCBool = false
		if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
			if !isDirectory.boolValue {
				throw FileAuthenticationStoreError.pathIsNotDirectory(directory)
			}
		} else {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		try setSecureDirectoryPermissions(at: directory)
	}
}

public enum FileAuthenticationStoreError: Error, Equatable, Sendable {
	case pathIsNotDirectory(URL)
}

private func setSecureDirectoryPermissions(at url: URL) throws {
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
}

private func setSecureFilePermissions(at url: URL) throws {
	try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
