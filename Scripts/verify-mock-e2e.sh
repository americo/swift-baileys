#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
	current_developer_dir="$(xcode-select -p 2>/dev/null || true)"
	if [[ "$current_developer_dir" == "/Library/Developer/CommandLineTools" &&
		! -e "$current_developer_dir/../SharedFrameworks/BuildServerProtocol.framework" ]]; then
		for candidate in \
			/Applications/Xcode.app/Contents/Developer \
			/Applications/Xcode-beta.app/Contents/Developer; do
			if [[ -x "$candidate/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" &&
				-e "$candidate/../SharedFrameworks/BuildServerProtocol.framework" ]]; then
				export DEVELOPER_DIR="$candidate"
				break
			fi
		done
	fi
fi

log_dir=".build/mock-e2e"
log_file="$log_dir/redacted-log.md"
mkdir -p "$log_dir"

cat > "$log_file" <<EOF
# SwiftBaileys Mock E2E Validation Log

- started_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- auth_state: not used; mock transports and in-memory stores only
- payload_policy: redacted suite names and test outcomes only

EOF

run_scenario() {
	local name="$1"
	local filter="$2"
	local output_file="$log_dir/${name// /-}.log"

	echo "==> $name"
	{
		echo "## $name"
		echo
		echo "- filter: \`$filter\`"
		echo "- started_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
	} >> "$log_file"

	swift test --filter "$filter" 2>&1 | tee "$output_file"
	if grep -q "No matching test cases were run" "$output_file"; then
		echo "No tests matched scenario: $name"
		exit 1
	fi

	{
		echo "- result: passed"
		echo "- finished_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
		echo
	} >> "$log_file"
}

echo "==> Swift toolchain"
xcrun --find swift
swift --version

run_scenario "Pairing and credential persistence" \
	"WhatsAppClientPairingCodeTests|PairSuccessProcessorTests|AuthenticationStateTests|AuthStoreTests|WhatsAppNativeSignalRuntimeTests"

run_scenario "Direct send and message cache" \
	"WhatsAppClientMessageSendTests|WhatsAppClientMessageRelayAliasTests|WhatsAppClientMessageDeviceTests"

run_scenario "Group send and sender-key fanout" \
	"WhatsAppClientGroupMessageSendTests|MessageRelayBuilderTests"

run_scenario "Status broadcast fanout" \
	"WhatsAppClientMessageRelayAliasTests/baileysRelayMessageStatusListSendsSenderKeyStanzaToBroadcast"

run_scenario "Retry receipt resend" \
	"WhatsAppClientMessageRetryResendTests|WhatsAppClientRetryRequestTests|PublicNativeSignalAdapterRetryTests"

run_scenario "Media upload download and reupload" \
	"WhatsAppClientMediaMessageSendTests|WhatsAppClientMediaDownloadTests|WhatsAppClientMediaRetryTests|WhatsAppMediaUploaderTests|WhatsAppMediaDownloaderTests|MediaRetryCipherTests"

run_scenario "App-state sync and persistence" \
	"WhatsAppClientAppStateSyncTests|WhatsAppClientAppStateTests|AppStatePatchDecoderTests|AppStateSnapshotDecoderTests"

run_scenario "Incoming events and ACK behavior" \
	"WhatsAppClientIncomingMessageAckTests|WhatsAppClientIncomingReceiptTests|WhatsAppClientIncomingPresenceTests|WhatsAppClientIncomingCallTests|WhatsAppClientIncomingNotificationTests|WhatsAppClientIncomingAckTests"

{
	echo "## Summary"
	echo
	echo "- result: passed"
	echo "- finished_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} >> "$log_file"

echo "SwiftBaileys mock e2e validation passed."
echo "Redacted log: $log_file"
