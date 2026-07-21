enum ForwardHighlyStructuredMessageMapper {
	static func message(from content: ReceivedHighlyStructuredMessageContent) -> Proto_Message {
		var hsm = Proto_Message.HighlyStructuredMessage()
		if let namespace = content.namespace {
			hsm.namespace = namespace
		}
		if let elementName = content.elementName {
			hsm.elementName = elementName
		}
		hsm.params = content.params
		if let fallbackLanguage = content.fallbackLanguage {
			hsm.fallbackLg = fallbackLanguage
		}
		if let fallbackLocale = content.fallbackLocale {
			hsm.fallbackLc = fallbackLocale
		}
		hsm.localizableParams = content.localizableParams.map(localizableParameter)
		if let deterministicLanguage = content.deterministicLanguage {
			hsm.deterministicLg = deterministicLanguage
		}
		if let deterministicLocale = content.deterministicLocale {
			hsm.deterministicLc = deterministicLocale
		}
		var message = Proto_Message()
		message.highlyStructuredMessage = hsm
		return message
	}

	private static func localizableParameter(
		_ content: ReceivedHSMLocalizableParameterContent
	) -> Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter {
		var parameter = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter()
		if let defaultValue = content.defaultValue {
			parameter.default = defaultValue
		}
		switch content.value {
		case .currency(let currency):
			var value = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMCurrency()
			if let currencyCode = currency.currencyCode {
				value.currencyCode = currencyCode
			}
			if let amount1000 = currency.amount1000 {
				value.amount1000 = amount1000
			}
			parameter.currency = value
		case .dateTime(let dateTime):
			parameter.dateTime = dateTimeParameter(dateTime)
		case nil:
			break
		}
		return parameter
	}

	private static func dateTimeParameter(
		_ content: ReceivedHSMDateTimeContent
	) -> Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime {
		var dateTime = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime()
		switch content {
		case .component(let component):
			var value = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent()
			if let dayOfWeek = component.dayOfWeek {
				value.dayOfWeek = switch dayOfWeek {
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
				case .unrecognized(let rawValue):
					.UNRECOGNIZED(rawValue)
				}
			}
			if let year = component.year {
				value.year = year
			}
			if let month = component.month {
				value.month = month
			}
			if let dayOfMonth = component.dayOfMonth {
				value.dayOfMonth = dayOfMonth
			}
			if let hour = component.hour {
				value.hour = hour
			}
			if let minute = component.minute {
				value.minute = minute
			}
			if let calendar = component.calendar {
				value.calendar = switch calendar {
				case .unknown:
					.unknown
				case .gregorian:
					.gregorian
				case .solarHijri:
					.solarHijri
				case .unrecognized(let rawValue):
					.UNRECOGNIZED(rawValue)
				}
			}
			dateTime.component = value
		case .unixEpoch(let timestamp):
			var value = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeUnixEpoch()
			if let timestamp {
				value.timestamp = timestamp
			}
			dateTime.unixEpoch = value
		}
		return dateTime
	}
}
