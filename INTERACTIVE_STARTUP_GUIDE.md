# Interactive CLI Startup Flow - User Guide

## Overview

The Convergence CLI now features an interactive startup flow that allows users to choose between FREE mode (browser automation) and API mode (with OpenRouter and other providers).

## Features

### 1. Interactive Setup on First Run

When you run the CLI for the first time (or after `/reset`), you'll be guided through a setup process:

```
╔═══════════════════════════════════════╗
║   CONVERGENCE CLI v∞.15.2            ║
╚═══════════════════════════════════════╝

Welcome! Let's set up your CLI.

Enable FREE mode? (browser automation with free LLM providers) [Y/n]:
```

### 2. FREE Mode (Default)

Choose FREE mode for browser automation with free LLM providers:

- **No API key required**
- **Multiple providers**: DuckDuckGo AI, HuggingChat, Perplexity, You.com, Poe
- **Auto-rotation** on rate limits
- **Session persistence**

Available providers:
- `duckduckgo` - Unlimited usage
- `huggingchat` - 50 queries/day
- `perplexity` - 20 queries/day
- `youchat` - 30 queries/day
- `poe` - 100 queries/day (requires login)

### 3. API Mode

Choose API mode for direct API access:

- **OpenRouter** (recommended) - Access multiple models through one API
- **OpenAI** - GPT-4o, GPT-4o-mini
- **Anthropic** - Claude Opus 4, Claude Sonnet 4
- **Google Gemini** - Gemini Pro, Gemini 2.0
- **DeepSeek** - DeepSeek Chat, DeepSeek Reasoner

#### OpenRouter Models

When using OpenRouter, you get access to:
- `deepseek-r1` - DeepSeek R1 (default)
- `claude-3.5` - Claude 3.5 Sonnet
- `gpt-4o` - GPT-4o
- `gemini-pro` - Gemini Pro

## Configuration

Configuration is saved to `~/.convergence/config.yml`:

```yaml
mode: api
provider: openrouter
api_keys:
  openrouter: sk-or-v1-...
model: deepseek/deepseek-r1
preferences:
  headless: true
  auto_rotate: true
```

File permissions are automatically set to `0600` (user read/write only) for security.

## Commands

### Mode and Provider Management

- `/mode` - Show current mode, provider, model, and usage stats
- `/provider [name]` - Switch provider (or list available providers)
- `/model [name]` - Switch model (API mode only, or list available models)
- `/key` - Update API key for current provider
- `/reset` - Clear saved preferences and restart setup

### Examples

```
> /mode
Current Configuration:
  Mode: api
  Provider: openrouter
  Model: deepseek/deepseek-r1
  Usage: 1250 tokens (850 prompt, 400 completion)

> /provider
Available API providers:
  • openrouter
  • openai
  • anthropic
  • gemini
  • deepseek

> /provider anthropic
✓ switched to anthropic

> /model
Available models for openrouter:
  • deepseek-r1 (deepseek/deepseek-r1)
  • claude-3.5 (anthropic/claude-3.5-sonnet)
  • gpt-4o (openai/gpt-4o)
  • gemini-pro (google/gemini-pro)

> /model claude-3.5
✓ switched to model: anthropic/claude-3.5-sonnet
```

## Switching Between Modes

You can switch between FREE and API mode by:

1. Using `/reset` to clear configuration
2. Restarting the CLI
3. Selecting your preferred mode in the interactive setup

## API Key Management

### Getting API Keys

- **OpenRouter**: https://openrouter.ai/keys
- **OpenAI**: https://platform.openai.com/api-keys
- **Anthropic**: https://console.anthropic.com/settings/keys
- **Gemini**: https://makersuite.google.com/app/apikey
- **DeepSeek**: https://platform.deepseek.com/api_keys

### Updating Keys

```
> /key
Enter API key: [hidden input]
✓ API key updated and saved
```

## Backward Compatibility

The CLI maintains backward compatibility with environment variables:

- `ANTHROPIC_API_KEY` - If set, defaults to API mode with Anthropic
- `NO_AUTO_INSTALL` - Prevents automatic gem installation

## Security

- API keys are stored with 0600 permissions (user read/write only)
- Input is hidden when entering API keys
- Config file location: `~/.convergence/config.yml`

## Troubleshooting

### No backend error

If you see "no backend", ensure either:
- Ferrum gem is installed for FREE mode
- Valid API key is configured for API mode

### Rate limits (FREE mode)

The CLI automatically rotates to other providers when rate limits are hit.

### API errors

Use `/key` to update your API key if you see authentication errors.

## Advanced Usage

### Custom Models (API Mode)

You can specify custom models when switching:

```
> /model gpt-4o
✓ switched to model: gpt-4o
```

### Provider-Specific Features

#### OpenRouter
- Includes HTTP-Referer header for better rate limits
- Access to multiple model providers
- Unified billing

#### Anthropic
- Uses native Anthropic API format
- Supports Claude Opus 4 and Sonnet 4

#### Gemini
- Uses Google's generativelanguage API
- Supports Gemini 2.0 Flash

## Future Enhancements

Planned features:
- Model usage statistics and cost tracking
- Custom model configurations
- Multiple saved profiles
- Conversation export/import
