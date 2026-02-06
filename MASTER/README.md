# MASTER

Self-modifying AI framework. Pure Ruby. OpenBSD.

Entry · `bin/cli`
Loader · `lib/master.rb`


## What It Does

Give it a task. It writes code, runs it, sees the result, iterates.
Can modify its own source. No npm, no Python—just Ruby and LLMs.


## For LLMs

You are MASTER. Execute via `sh` or `ruby` fenced blocks.
Files in `lib/` are yours to improve.


## Structure

    bin/cli              Start here
    bin/bot              Multi-platform bot launcher
    lib/master.rb        Autoloader
    lib/cli.rb           REPL and commands
    lib/cli_v226.rb      Unified CLI (interactive + batch)
    lib/llm.rb           Model routing (9 tiers)
    lib/executor.rb      Runs code blocks from responses
    lib/safety.rb        Guardrails
    lib/evolve.rb        Self-optimization loop
    lib/chamber.rb       Multi-model deliberation
    lib/postpro.rb       Cinematic film emulation (12 stocks, 12 presets)
    lib/principles/      45 constitutional rules
    lib/config/          YAML settings
    lib/personas/        Character modes
    lib/unified/         v226 unified framework components


## Commands

    ask           Chat
    scan          Analyze cwd
    refactor      Improve code
    evolve        Converge until <2% gain
    chamber       Multi-model debate
    tier          Switch model class
    dashboard     Show live dashboard
    remember      Store in long-term memory
    recall        Search long-term memory
    memory-stats  Memory system status
    help          List all


## Dashboard

View live statistics and metrics:

```bash
bin/cli dashboard
```

Shows:
- Cost breakdown by model
- Recent tasks
- Memory statistics
- System health


## Memory

MASTER uses Weaviate for persistent vector memory.

### Store Information
```bash
bin/cli remember "Important fact" --tags important,fact --source documentation
```

### Recall Information
```bash
bin/cli recall "what did I learn about X"
```

### Memory Stats
```bash
bin/cli memory-stats
```

Memory persists across sessions and improves over time.

### Weaviate Setup

MASTER uses Weaviate for vector memory. Run via Docker:

```bash
docker run -d \
  -p 8080:8080 \
  -e QUERY_DEFAULTS_LIMIT=25 \
  -e AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true \
  -e PERSISTENCE_DATA_PATH='/var/lib/weaviate' \
  -e DEFAULT_VECTORIZER_MODULE='text2vec-openai' \
  -e ENABLE_MODULES='text2vec-openai' \
  -e OPENAI_APIKEY='your-key' \
  semitechnologies/weaviate:latest
```

Or use Weaviate Cloud: https://console.weaviate.cloud/


## Models

    cheap       DeepSeek
    fast        Grok
    strong      Sonnet
    frontier    Opus
    code        Codestral


## Multi-Platform Bot

MASTER can run as a multi-platform chatbot on Discord, Telegram, Slack, and Twitter/X.

### Setup

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Configure platforms:**
   
   Edit `config/platforms.yml` and enable desired platforms:
   ```yaml
   discord:
     enabled: true
     token: <%= ENV['DISCORD_BOT_TOKEN'] %>
   ```

3. **Set environment variables:**
   
   **Discord:**
   ```bash
   export DISCORD_BOT_TOKEN="your_token_here"
   export DISCORD_PUBLIC_KEY="your_public_key"  # For webhook verification
   ```
   
   **Telegram:**
   ```bash
   export TELEGRAM_BOT_TOKEN="your_token_here"
   export TELEGRAM_WEBHOOK_SECRET="your_secret"  # Optional for webhooks
   ```
   
   **Slack:**
   ```bash
   export SLACK_BOT_TOKEN="xoxb-your-token"
   export SLACK_SIGNING_SECRET="your_secret"  # For webhook verification
   ```
   
   **Twitter/X:**
   ```bash
   export TWITTER_ACCESS_TOKEN="your_token"
   export TWITTER_ACCESS_SECRET="your_secret"
   export TWITTER_CONSUMER_KEY="your_key"
   export TWITTER_CONSUMER_SECRET="your_secret"
   ```

4. **Start the bot:**
   ```bash
   bin/bot
   ```

### Token Acquisition

**Discord:**
1. Go to https://discord.com/developers/applications
2. Create New Application
3. Go to "Bot" → Reset Token
4. Copy token to `DISCORD_BOT_TOKEN`
5. Enable "Message Content Intent"
6. Go to "General Information" → Copy Public Key to `DISCORD_PUBLIC_KEY`

**Telegram:**
1. Message @BotFather on Telegram
2. Send `/newbot` and follow prompts
3. Copy token to `TELEGRAM_BOT_TOKEN`
4. Set webhook: `https://yourserver.com/webhook/telegram`

**Slack:**
1. Go to https://api.slack.com/apps
2. Create New App → From scratch
3. Go to "OAuth & Permissions"
4. Add scopes: `chat:write`, `app_mentions:read`, `channels:history`
5. Install to workspace
6. Copy "Bot User OAuth Token" to `SLACK_BOT_TOKEN`
7. Go to "Basic Information" → Copy "Signing Secret" to `SLACK_SIGNING_SECRET`

**Twitter/X:**
1. Go to https://developer.twitter.com/
2. Create App with Read/Write permissions
3. Generate Access Token & Secret
4. Copy all credentials to respective ENV vars

### Webhook Setup

For production deployments, configure webhooks for each platform:

**Discord:**
```
POST https://yourserver.com/webhook/discord
Headers:
  X-Signature-Timestamp: timestamp
  X-Signature-Ed25519: signature
```

**Telegram:**
```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://yourserver.com/webhook/telegram"
```

**Slack:**
```
POST https://yourserver.com/webhook/slack
Headers:
  X-Slack-Request-Timestamp: timestamp
  X-Slack-Signature: signature
```

**Twitter/X:**
```
POST https://yourserver.com/webhook/twitter
Headers:
  X-Twitter-Webhooks-Signature: signature
```

### Configuration

Edit `config/platforms.yml` to customize:

- Channel whitelists (restrict bot to specific channels)
- Rate limits per platform
- Message formatting options
- Retry policies
- Error handling behavior

### Troubleshooting

**Bot not responding:**
- Check platform is enabled in `config/platforms.yml`
- Verify token is set correctly in environment
- Check logs in `~/.master/var/audit.log`
- Ensure bot has proper permissions in Discord/Slack

**Rate limit errors:**
- Adjust rate limits in config
- Twitter/X has strict rate limits - use sparingly
- Consider implementing message queuing

**Webhook verification failing:**
- Ensure signing secrets are set correctly
- Check server is accessible from internet
- Verify webhook URLs in platform settings


## Environment

    OPENROUTER_API_KEY    Required
    REPLICATE_API_TOKEN   Media generation
    
    # Platform tokens (for bot mode)
    DISCORD_BOT_TOKEN
    TELEGRAM_BOT_TOKEN
    SLACK_BOT_TOKEN
    TWITTER_ACCESS_TOKEN


## Design

Typography through contrast, not decoration.
Whitespace is layout. Proximity beats borders.
Success whispers. Errors speak.
Five icons: `✓ ✗ ! · →`

Zsh over Bash. Parameter expansion over forks.
Calm palette. Monospace constraints respected.


## Unified Framework v226

MASTER v226 "Unified Deep Debug" merges powerful debugging frameworks:

### Interactive Mode
```bash
ruby lib/cli_v226.rb
```
Conversational REPL with visual mood indicators and persona switching.

### Batch Analysis
```bash
ruby lib/cli_v226.rb file.rb            # Basic analysis
ruby lib/cli_v226.rb file.rb --debug    # 8-phase bug hunting
ruby lib/cli_v226.rb file.rb --json     # JSON output
```

### Features
- **Enhanced Postpro**: 12 film stocks, 12 presets, caching
- **Bug Hunting**: 8-phase systematic debugging protocol
- **Resilience**: Act-react loop, never give up approach
- **Constitutional AI**: 7 personas, 12 biases, 7 depth techniques
- **Systematic**: Required workflows (tree, clean, diff, logs)
- **Mood Indicators**: Visual feedback (idle, thinking, working, success, error)
- **Persona Modes**: Character-based output (ronin, verbose, hacker, poet, detective)

### Documentation
See `docs/UNIFIED_v226.md` for complete documentation.

### Configuration
Edit `config/master_v226.yml` to customize behavior.


## License

MIT

*v52 · Ruby · OpenBSD · Constitutional · Unified v226*
