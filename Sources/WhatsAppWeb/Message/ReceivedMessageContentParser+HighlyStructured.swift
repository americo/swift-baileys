extension ReceivedMessageContentParser {
	static func highlyStructuredContent(
		_ hsm: Proto_Message.HighlyStructuredMessage
	) -> ReceivedHighlyStructuredMessageContent {
		ReceivedHighlyStructuredMessageContent(
			namespace: hsm.hasNamespace ? hsm.namespace : nil,
			elementName: hsm.hasElementName ? hsm.elementName : nil,
			params: hsm.params,
			fallbackLanguage: hsm.hasFallbackLg ? hsm.fallbackLg : nil,
			fallbackLocale: hsm.hasFallbackLc ? hsm.fallbackLc : nil,
			localizableParams: hsm.localizableParams.map(hsmLocalizableParameterContent),
			deterministicLanguage: hsm.hasDeterministicLg ? hsm.deterministicLg : nil,
			deterministicLocale: hsm.hasDeterministicLc ? hsm.deterministicLc : nil
		)
	}

	private static func hsmLocalizableParameterContent(
		_ parameter: Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter
	) -> ReceivedHSMLocalizableParameterContent {
		let value: ReceivedHSMLocalizableParameterValue? = switch parameter.paramOneof {
		case .currency(let currency):
			.currency(ReceivedHSMCurrencyContent(
				currencyCode: currency.hasCurrencyCode ? currency.currencyCode : nil,
				amount1000: currency.hasAmount1000 ? currency.amount1000 : nil
			))
		case .dateTime(let dateTime):
			hsmDateTimeContent(dateTime).map { .dateTime($0) }
		case nil:
			nil
		}

		return ReceivedHSMLocalizableParameterContent(
			defaultValue: parameter.hasDefault ? parameter.default : nil,
			value: value
		)
	}

	private static func hsmDateTimeContent(
		_ dateTime: Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime
	) -> ReceivedHSMDateTimeContent? {
		switch dateTime.datetimeOneof {
		case .component(let component):
			.component(ReceivedHSMDateTimeComponentContent(
				dayOfWeek: component.hasDayOfWeek ? hsmDayOfWeek(component.dayOfWeek) : nil,
				year: component.hasYear ? component.year : nil,
				month: component.hasMonth ? component.month : nil,
				dayOfMonth: component.hasDayOfMonth ? component.dayOfMonth : nil,
				hour: component.hasHour ? component.hour : nil,
				minute: component.hasMinute ? component.minute : nil,
				calendar: component.hasCalendar ? hsmCalendar(component.calendar) : nil
			))
		case .unixEpoch(let epoch):
			.unixEpoch(timestamp: epoch.hasTimestamp ? epoch.timestamp : nil)
		case nil:
			nil
		}
	}

	private static func hsmDayOfWeek(
		_ day: Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent.DayOfWeekType
	) -> ReceivedHSMDayOfWeek {
		switch day {
		case .unknown:
			.unknown
		case .monday:
			.monday
		case .tuesday:
			.tuesday
		case .wednesday:
			.wednesday
		case .thursday:
			.thursday
		case .friday:
			.friday
		case .saturday:
			.saturday
		case .sunday:
			.sunday
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}

	private static func hsmCalendar(
		_ calendar: Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent.CalendarType
	) -> ReceivedHSMCalendar {
		switch calendar {
		case .unknown:
			.unknown
		case .gregorian:
			.gregorian
		case .solarHijri:
			.solarHijri
		case .UNRECOGNIZED(let value):
			.unrecognized(value)
		}
	}
}
