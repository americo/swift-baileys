import Foundation

public struct WAMDefinitions: Sendable {
	public let events: [WAMEventDefinition]
	public let globals: [WAMGlobalDefinition]

	public init(events: [WAMEventDefinition], globals: [WAMGlobalDefinition] = []) {
		self.events = events
		self.globals = globals
	}

	public func event(named name: String) -> WAMEventDefinition? {
		events.first { $0.name == name }
	}

	public func global(named name: String) -> WAMGlobalDefinition? {
		globals.first { $0.name == name }
	}

	public static func web() throws -> WAMDefinitions {
		try bundledWebDefinitions.get()
	}

	private static let bundledWebDefinitions: Result<WAMDefinitions, WAMDefinitionsError> = {
		do {
			return .success(try loadBundledWebDefinitions())
		} catch let error as WAMDefinitionsError {
			return .failure(error)
		} catch {
			return .failure(.invalidResource)
		}
	}()

	private static func loadBundledWebDefinitions() throws -> WAMDefinitions {
		guard let url = Bundle.module.url(forResource: "definitions", withExtension: "json") else {
			throw WAMDefinitionsError.missingResource
		}

		do {
			let data = try Data(contentsOf: url)
			let resource = try JSONDecoder().decode(WAMDefinitionsResource.self, from: data)
			return WAMDefinitions(
				events: resource.events.map {
					WAMEventDefinition(name: $0.name, id: $0.id, weight: $0.weight, props: $0.props)
				},
				globals: resource.globals.map {
					WAMGlobalDefinition(name: $0.name, id: $0.id)
				}
			)
		} catch {
			throw WAMDefinitionsError.invalidResource
		}
	}
}

public enum WAMDefinitionsError: Error, Equatable, Sendable {
	case missingResource
	case invalidResource
}

private struct WAMDefinitionsResource: Decodable {
	let events: [WAMEventResource]
	let globals: [WAMGlobalResource]
}

private struct WAMEventResource: Decodable {
	let name: String
	let id: Int
	let weight: Int
	let props: [String: Int]
}

private struct WAMGlobalResource: Decodable {
	let name: String
	let id: Int
}
