import Testing
@testable import WhatsAppWeb

@Suite("Received message highly structured parser")
struct ReceivedMessageHighlyStructuredParserTests {
	@Test("parses highly structured messages")
	func parsesHighlyStructuredMessages() throws {
		var message = Proto_Message()
		var hsm = Proto_Message.HighlyStructuredMessage()
		hsm.namespace = "commerce"
		hsm.elementName = "order_update"
		hsm.params = ["Alice", "A-123"]
		hsm.fallbackLg = "en"
		hsm.fallbackLc = "US"
		hsm.deterministicLg = "pt"
		hsm.deterministicLc = "MZ"
		message.highlyStructuredMessage = hsm

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .highlyStructured(ReceivedHighlyStructuredMessageContent(
			namespace: "commerce",
			elementName: "order_update",
			params: ["Alice", "A-123"],
			fallbackLanguage: "en",
			fallbackLocale: "US",
			localizableParams: [],
			deterministicLanguage: "pt",
			deterministicLocale: "MZ"
		)))
		#expect(try content.mediaDownloadRequest() == nil)
	}

	@Test("parses localizable currency and date time parameters")
	func parsesLocalizableCurrencyAndDateTimeParameters() throws {
		var currency = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMCurrency()
		currency.currencyCode = "USD"
		currency.amount1000 = 12_345_000
		var currencyParam = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter()
		currencyParam.default = "$12,345.00"
		currencyParam.currency = currency

		var component = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent()
		component.dayOfWeek = .friday
		component.year = 2026
		component.month = 5
		component.dayOfMonth = 31
		component.hour = 14
		component.minute = 45
		component.calendar = .gregorian
		var dateTime = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime()
		dateTime.component = component
		var dateParam = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter()
		dateParam.default = "Friday"
		dateParam.dateTime = dateTime

		var unixEpoch = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeUnixEpoch()
		unixEpoch.timestamp = 1_717_900_000
		var unixDateTime = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime()
		unixDateTime.unixEpoch = unixEpoch
		var unixParam = Proto_Message.HighlyStructuredMessage.HSMLocalizableParameter()
		unixParam.dateTime = unixDateTime

		var hsm = Proto_Message.HighlyStructuredMessage()
		hsm.localizableParams = [currencyParam, dateParam, unixParam]
		var message = Proto_Message()
		message.highlyStructuredMessage = hsm

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .highlyStructured(ReceivedHighlyStructuredMessageContent(
			namespace: nil,
			elementName: nil,
			params: [],
			fallbackLanguage: nil,
			fallbackLocale: nil,
			localizableParams: [
				ReceivedHSMLocalizableParameterContent(
					defaultValue: "$12,345.00",
					value: .currency(ReceivedHSMCurrencyContent(currencyCode: "USD", amount1000: 12_345_000))
				),
				ReceivedHSMLocalizableParameterContent(
					defaultValue: "Friday",
					value: .dateTime(.component(ReceivedHSMDateTimeComponentContent(
						dayOfWeek: .friday,
						year: 2026,
						month: 5,
						dayOfMonth: 31,
						hour: 14,
						minute: 45,
						calendar: .gregorian
					)))
				),
				ReceivedHSMLocalizableParameterContent(
					defaultValue: nil,
					value: .dateTime(.unixEpoch(timestamp: 1_717_900_000))
				)
			],
			deterministicLanguage: nil,
			deterministicLocale: nil
		)))
	}

	@Test("preserves absent highly structured fields")
	func preservesAbsentHighlyStructuredFields() throws {
		var message = Proto_Message()
		message.highlyStructuredMessage = Proto_Message.HighlyStructuredMessage()

		let content = try #require(ReceivedMessageContentParser.parse(message))

		#expect(content == .highlyStructured(ReceivedHighlyStructuredMessageContent(
			namespace: nil,
			elementName: nil,
			params: [],
			fallbackLanguage: nil,
			fallbackLocale: nil,
			localizableParams: [],
			deterministicLanguage: nil,
			deterministicLocale: nil
		)))
	}
}
