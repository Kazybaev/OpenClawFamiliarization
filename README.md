# OpenClaw с Gemini и Telegram с нуля

Этот документ описывает полное развёртывание текущей конфигурации OpenClaw без
клонирования этого проекта. После выполнения инструкции получится:

- OpenClaw CLI, установленный в `~/.openclaw`;
- локальный Gateway на `http://127.0.0.1:18789/`;
- Gateway как пользовательский systemd-сервис;
- Gemini API как провайдер модели;
- модель `google/gemini-2.5-flash` по умолчанию;
- Telegram-бот как канал общения;
- отдельные диалоги для каждого пользователя Telegram;
- профиль инструментов `coding`.

Инструкция проверена для Linux с systemd. Текущая установленная версия OpenClaw:
`2026.6.1`. Установщик может поставить более новую совместимую версию.

## 1. Получить ключи

Нужны два обязательных секрета:

1. Создать Gemini API key в [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Открыть Telegram-бота [@BotFather](https://t.me/BotFather), выполнить
   `/newbot` и сохранить выданный токен.

Gateway token сгенерируем локально. Никогда не публикуйте эти три значения.

## 2. Установить системные зависимости

Для Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y curl ca-certificates openssl
```

Системный Node.js устанавливать отдельно не обязательно: официальный установщик
OpenClaw устанавливает подходящий Node.js внутрь `~/.openclaw/tools`.

## 3. Установить OpenClaw

```bash
curl -fsSL https://openclaw.ai/install-cli.sh | bash
```

Добавить CLI в текущую сессию и проверить установку:

```bash
export PATH="$HOME/.openclaw/bin:$PATH"
openclaw --version
```

Чтобы команда была доступна после нового входа в систему:

```bash
printf '\nexport PATH="$HOME/.openclaw/bin:$PATH"\n' >> "$HOME/.bashrc"
source "$HOME/.bashrc"
```

## 4. Создать локальный каталог настройки

Это заменяет клонирование проекта:

```bash
mkdir -p "$HOME/OpenClawBot"
cd "$HOME/OpenClawBot"
```

Создать `.env`:

```bash
GATEWAY_TOKEN="$(openssl rand -hex 32)"

cat > .env <<EOF
GEMINI_API_KEY=ВСТАВИТЬ_GEMINI_API_KEY
TELEGRAM_BOT_TOKEN=ВСТАВИТЬ_TELEGRAM_BOT_TOKEN
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
OPENCLAW_DEFAULT_MODEL=google/gemini-2.5-flash
EOF

chmod 600 .env
unset GATEWAY_TOKEN
```

Заменить два значения `ВСТАВИТЬ_...` своими ключами:

```bash
nano .env
```

Создать `.gitignore`, чтобы секреты случайно не попали в Git:

```bash
cat > .gitignore <<'EOF'
.env
.env.*
!.env.example

node_modules/
npm-debug.log*

.openclaw/
*.log
EOF
```

## 5. Создать скрипт полной настройки

Создать `start-openclaw.sh`:

```bash
cat > start-openclaw.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_BIN="${OPENCLAW_BIN:-$HOME/.openclaw/bin/openclaw}"
DEFAULT_MODEL="${OPENCLAW_DEFAULT_MODEL:-google/gemini-2.5-flash}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ ! -x "$OPENCLAW_BIN" ]]; then
  echo "OpenClaw не найден: $OPENCLAW_BIN" >&2
  exit 1
fi

if [[ -z "${GEMINI_API_KEY:-}" && -z "${GOOGLE_API_KEY:-}" ]]; then
  echo "Укажите GEMINI_API_KEY или GOOGLE_API_KEY в .env" >&2
  exit 1
fi

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "Укажите TELEGRAM_BOT_TOKEN в .env" >&2
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
"$OPENCLAW_BIN" models set "$DEFAULT_MODEL"
"$OPENCLAW_BIN" config set session.dmScope per-channel-peer
"$OPENCLAW_BIN" config set tools.profile coding
"$OPENCLAW_BIN" config set channels.telegram.dmPolicy open
"$OPENCLAW_BIN" config set channels.telegram.allowFrom '["*"]' --strict-json

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user import-environment \
    GEMINI_API_KEY GOOGLE_API_KEY TELEGRAM_BOT_TOKEN OPENCLAW_GATEWAY_TOKEN || true
fi

"$OPENCLAW_BIN" gateway restart
"$OPENCLAW_BIN" gateway status
SCRIPT

chmod +x start-openclaw.sh
```

Запустить настройку:

```bash
./start-openclaw.sh
```

Скрипт можно запускать повторно. Он выполняет onboarding, включает плагины Google
и Telegram, добавляет Telegram-канал, задаёт модель, профиль инструментов,
разделение диалогов и политику личных сообщений, затем перезапускает Gateway.

## 6. Привязать свой Telegram-аккаунт

1. Отправить созданному Telegram-боту команду `/pair`.
2. Посмотреть ожидающие привязки:

```bash
openclaw pairing list telegram
```

3. Подтвердить выданный код:

```bash
openclaw pairing approve telegram КОД_ИЗ_TELEGRAM
```

4. Отправить боту обычное сообщение и проверить ответ.

После подтверждения Telegram ID владельца добавляется в конфигурацию OpenClaw.

## 7. Проверить результат

```bash
openclaw status
openclaw gateway status
openclaw models list
systemctl --user status openclaw-gateway.service
```

Панель Gateway доступна только с этого компьютера:

```text
http://127.0.0.1:18789/
```

Это намеренно: `gateway.bind=loopback` не открывает Gateway во внешнюю сеть.

Основная конфигурация будет создана здесь:

```text
~/.openclaw/openclaw.json
```

Ключевые значения текущей конфигурации:

```json
{
  "agents": {
    "defaults": {
      "model": { "primary": "google/gemini-2.5-flash" }
    }
  },
  "gateway": {
    "mode": "local",
    "port": 18789,
    "bind": "loopback",
    "auth": { "mode": "token" }
  },
  "session": { "dmScope": "per-channel-peer" },
  "tools": { "profile": "coding" },
  "plugins": {
    "entries": {
      "google": { "enabled": true },
      "telegram": { "enabled": true }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "name": "telegram",
      "dmPolicy": "open",
      "allowFrom": ["*"]
    }
  }
}
```

Секреты и Telegram ID в этот пример намеренно не включены.

## 8. Управление сервисом

```bash
systemctl --user restart openclaw-gateway.service
systemctl --user stop openclaw-gateway.service
systemctl --user start openclaw-gateway.service
journalctl --user -u openclaw-gateway.service -f
```

Чтобы Gateway продолжал работать после выхода пользователя из SSH-сессии:

```bash
sudo loginctl enable-linger "$(whoami)"
systemctl --user enable --now openclaw-gateway.service
```

Если `systemctl --user` не видит пользовательскую сессию:

```bash
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service
```

## 9. Частые операции

Сменить модель:

```bash
openclaw models set google/gemini-2.5-flash
```

Повторно посмотреть или подтвердить Telegram pairing:

```bash
openclaw pairing list telegram
openclaw pairing approve telegram КОД
```

Диагностика:

```bash
openclaw doctor
openclaw status
openclaw gateway status
```

Обновить OpenClaw:

```bash
curl -fsSL https://openclaw.ai/install-cli.sh | bash
openclaw gateway restart
openclaw --version
```

## 10. Резервная копия и перенос

Остановить сервис и сохранить состояние:

```bash
systemctl --user stop openclaw-gateway.service
tar -czf "openclaw-backup-$(date +%F).tar.gz" "$HOME/.openclaw" "$HOME/OpenClawBot/.env"
systemctl --user start openclaw-gateway.service
```

Архив содержит API keys, Gateway token, Telegram pairing и историю. Хранить его
нужно как секрет. Для чистой установки резервная копия не нужна: достаточно
заново выполнить шаги 1-7.

## Безопасность

- Не добавлять `.env`, `~/.openclaw/openclaw.json` и backup-архивы в Git.
- Если ключ когда-либо попал в README, `.env.example`, чат или публичный Git,
  немедленно отозвать его и создать новый.
- Для Telegram-бота с `dmPolicy=open` писать боту может любой пользователь.
  Pairing определяет владельца, но публичному боту всё равно нельзя выдавать
  опасные системные права.
- Не менять `gateway.bind` с `loopback` без firewall, TLS и понимания рисков.

## Полное удаление

Перед удалением при необходимости сделать резервную копию.

```bash
systemctl --user disable --now openclaw-gateway.service
rm -rf "$HOME/.openclaw"
rm -rf "$HOME/OpenClawBot"
systemctl --user daemon-reload
```
