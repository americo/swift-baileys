enum StringPresence {
	static func isNullOrEmpty(_ value: String?) -> Bool {
		value == nil || value == ""
	}
}
