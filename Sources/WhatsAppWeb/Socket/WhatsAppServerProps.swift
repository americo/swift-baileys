struct WhatsAppServerProps: Sendable {
	var privacyTokenOnOneToOne = true
	var profilePicturePrivacyToken = true
	var lidTrustedTokenIssueToLID = false

	mutating func apply(_ props: [String: String]) {
		if let value = props["10518"] ?? props["privacy_token_sending_on_all_1_on_1_messages"] {
			privacyTokenOnOneToOne = value == "true" || value == "1"
		}

		if let value = props["9666"] ?? props["profile_scraping_privacy_token_in_photo_iq"] {
			profilePicturePrivacyToken = value == "true" || value == "1"
		}

		if let value = props["14303"] ?? props["lid_trusted_token_issue_to_lid"] {
			lidTrustedTokenIssueToLID = value == "true" || value == "1"
		}
	}
}
