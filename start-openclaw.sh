#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_BIN="${OPENCLAW_BIN:-$HOME/.openclaw/bin/openclaw}"
DEFAULT_MODEL="${OPENCLAW_DEFAULT_MODEL:-google/gemini-2.5-flash}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ ! -x "$OPENCLAW_BIN" ]]; then
  echo "openclaw not found at $OPENCLAW_BIN" >&2
  echo "Install with: curl -fsSL https://openclaw.ai/install-cli.sh | bash" >&2
  exit 1
fi

if [[ -z "${GEMINI_API_KEY:-}" && -z "${GOOGLE_API_KEY:-}" ]]; then
  echo "Set GEMINI_API_KEY or GOOGLE_API_KEY in .env before configuring Gemini." >&2
  exit 1
fi

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "Set TELEGRAM_BOT_TOKEN in .env before configuring Telegram." >&2
  exit 1
fi

"$OPENCLAW_BIN" onboard \
  --non-interactive \
  --accept-risk \
  --mode local \
  --flow quickstart \
  --daemon-runtime node \
  --install-daemon \
  --auth-choice gemini-api-key \
  --gemini-api-key "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}" \
  --gateway-bind loopback \
  --gateway-auth token \
  ${OPENCLAW_GATEWAY_TOKEN:+--gateway-token "$OPENCLAW_GATEWAY_TOKEN"} \
  --skip-channels

"$OPENCLAW_BIN" plugins enable google || true
"$OPENCLAW_BIN" channels add --channel telegram --use-env --name telegram
"$OPENCLAW_BIN" channels add --channel whatsapp --name whatsapp
"$OPENCLAW_BIN" models set "$DEFAULT_MODEL"
"$OPENCLAW_BIN" config set session.dmScope per-channel-peer
"$OPENCLAW_BIN" config set tools.profile coding
"$OPENCLAW_BIN" config set channels.telegram.dmPolicy open
"$OPENCLAW_BIN" config set channels.telegram.allowFrom '["*"]' --strict-json
"$OPENCLAW_BIN" config set channels.whatsapp.dmPolicy open
"$OPENCLAW_BIN" config set channels.whatsapp.allowFrom '["*"]' --strict-json
"$OPENCLAW_BIN" config set channels.whatsapp.groupPolicy disabled
"$OPENCLAW_BIN" config unset channels.whatsapp.groupAllowFrom || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user import-environment \
    GEMINI_API_KEY \
    GOOGLE_API_KEY \
    TELEGRAM_BOT_TOKEN \
    OPENCLAW_GATEWAY_TOKEN || true
fi

"$OPENCLAW_BIN" gateway restart
"$OPENCLAW_BIN" gateway status

cat <<'NEXT'

Telegram pairing:
1. Send /pair to your Telegram bot.
2. Run: openclaw pairing list telegram
3. Run: openclaw pairing approve telegram <CODE>
4. Send a test message to the bot.

WhatsApp pairing:
1. Run: openclaw channels login --channel whatsapp
2. Open WhatsApp on your phone.
3. Go to Linked Devices and scan the QR code.
4. Run: openclaw channels status
NEXT
