# Multi-Platform Bot Quick Start Guide

## Prerequisites

1. Ruby 3.0+ installed
2. OpenRouter API key (for LLM)
3. Bot tokens from desired platforms

## Installation

```bash
cd MASTER
bundle install
```

## Configuration

1. Copy example environment file:
```bash
cp .env.bot.example .env
```

2. Edit `.env` and add your tokens:
```bash
# Required
OPENROUTER_API_KEY=sk-or-...

# Optional - enable platforms you want
DISCORD_BOT_TOKEN=...
TELEGRAM_BOT_TOKEN=...
```

3. Edit `config/platforms.yml` to enable platforms:
```yaml
discord:
  enabled: true  # Set to true
  token: <%= ENV['DISCORD_BOT_TOKEN'] %>
```

## Running the Bot

```bash
bin/bot
```

You should see:
```
MASTER Bot
Multi-platform AI assistant

✓ discord started
✓ Server: http://localhost:8080
```

## Testing Locally

### Discord
1. Invite bot to your server
2. Send a message in a channel the bot can see
3. Bot will respond using MASTER's CLI processing

### Telegram
1. Start a chat with your bot
2. Send `/start` or any message
3. Bot responds with MASTER's AI

## Architecture

```
User Message → Platform Adapter → Event Bus → Bot Manager → CLI → LLM → Response
```

## Troubleshooting

**Bot not responding:**
1. Check platform is enabled in config
2. Verify token in environment
3. Check bot permissions in platform
4. Review audit logs for errors

**Webhook verification failing:**
1. Ensure signing secrets are correct
2. Check server is publicly accessible
3. Verify webhook URLs in platform settings
