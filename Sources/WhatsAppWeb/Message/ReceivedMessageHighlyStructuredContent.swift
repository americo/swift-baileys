public struct ReceivedHighlyStructuredMessageContent: Equatable, Sendable {
	public let namespace: String?
	public let elementName: String?
	public let params: [String]
	public let fallbackLanguage: String?
	public let fallbackLocale: String?
	public let localizableParams: [ReceivedHSMLocalizableParameterContent]
	public let deterministicLanguage: String?
	public let deterministicLocale: String?

	public init(
		namespace: String?,
		elementName: String?,
		params: [String],
		fallbackLanguage: String?,
		fallbackLocale: String?,
		localizableParams: [ReceivedHSMLocalizableParameterContent],
		deterministicLanguage: String?,
		deterministicLocale: String?
	) {
		self.namespace = namespace
		self.elementName = elementName
		self.params = params
		self.fallbackLanguage = fallbackLanguage
		self.fallbackLocale = fallbackLocale
		self.localizableParams = localizableParams
		self.deterministicLanguage = deterministicLanguage
		self.deterministicLocale = deterministicLocale
	}
}

public struct ReceivedHSMLocalizableParameterContent: Equatable, Sendable {
	public let defaultValue: String?
	public let value: ReceivedHSMLocalizableParameterValue?

	public init(defaultValue: String?, value: ReceivedHSMLocalizableParameterValue?) {
		self.defaultValue = defaultValue
		self.value = value
	}
}

public enum ReceivedHSMLocalizableParameterValue: Equatable, Sendable {
	case currency(ReceivedHSMCurrencyContent)
	case dateTime(ReceivedHSMDateTimeContent)
}

public struct ReceivedHSMCurrencyContent: Equatable, Sendable {
	public let currencyCode: String?
	public let amount1000: Int64?

	public init(currencyCode: String?, amount1000: Int64?) {
		self.currencyCode = currencyCode
		self.amount1000 = amount1000
	}
}

public enum ReceivedHSMDateTimeContent: Equatable, Sendable {
	case component(ReceivedHSMDateTimeComponentContent)
	case unixEpoch(timestamp: Int64?)
}

public struct ReceivedHSMDateTimeComponentContent: Equatable, Sendable {
	public let dayOfWeek: ReceivedHSMDayOfWeek?
	public let year: UInt32?
	public let month: UInt32?
	public let dayOfMonth: UInt32?
	public let hour: UInt32?
	public let minute: UInt32?
	public let calendar: ReceivedHSMCalendar?

	public init(
		dayOfWeek: ReceivedHSMDayOfWeek?,
		year: UInt32?,
		month: UInt32?,
		dayOfMonth: UInt32?,
		hour: UInt32?,
		minute: UInt32?,
		calendar: ReceivedHSMCalendar?
	) {
		self.dayOfWeek = dayOfWeek
		self.year = year
		self.month = month
		self.dayOfMonth = dayOfMonth
		self.hour = hour
		self.minute = minute
		self.calendar = calendar
	}
}

public enum ReceivedHSMDayOfWeek: Equatable, Sendable {
	case unknown
	case monday
	case tuesday
	case wednesday
	case thursday
	case friday
	case saturday
	case sunday
	case unrecognized(Int)
}

public enum ReceivedHSMCalendar: Equatable, Sendable {
	case unknown
	case gregorian
	case solarHijri
	case unrecognized(Int)
}
