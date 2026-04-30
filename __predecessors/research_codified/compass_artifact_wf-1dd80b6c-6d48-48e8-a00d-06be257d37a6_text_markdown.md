# Designing a master.json configuration for GitHub Copilot CLI

**GitHub's new Copilot CLI (public preview September 2025) replaces the deprecated gh-copilot extension with an agentic, Node.js-based architecture.** This presents a unique opportunity to design a comprehensive configuration system that leverages modern zsh integration patterns, established CLI configuration conventions, and AI-tool best practices. The optimal master.json design should embrace MCP extensibility, support granular tool permissions, enable custom agents, and integrate seamlessly with modern shell environments.

## The Copilot CLI architecture shift fundamentally changes configuration needs

The new Copilot CLI (`npm install -g @github/copilot`) represents a dramatic departure from the old gh-copilot extension. Where the legacy tool offered simple `suggest` and `explain` commands, the new CLI is a full agentic AI assistant powered by **Claude Sonnet 4** (with GPT-5 available via environment variable). It can read files, write code, execute shell commands, and interact with GitHub's API through a built-in MCP server.

Current configuration is minimal, stored in `~/.copilot/`:

| File | Purpose |
|------|---------|
| `config.json` | Trusted folders array, basic settings |
| `mcp-config.json` | MCP server definitions |
| Custom instructions | `.github/copilot-instructions.md` per repository |
| Custom agents | `~/.copilot/agents/` or `.github/agents/` |

This sparse configuration system leaves significant room for a comprehensive master.json that could consolidate settings, provide defaults, and enable advanced customization while following established CLI patterns from tools like ESLint, TypeScript, and modern AI assistants like aichat and Shell-GPT.

## Modern zsh patterns inform shell integration design

The zsh ecosystem has matured significantly through 2023-2025, with **zinit's Turbo mode** delivering 50-80% faster startup times through deferred loading, and frameworks like Powerlevel10k pioneering instant prompt techniques. A master.json should enable these optimizations for Copilot integration.

Key zsh patterns to support include **completion system integration** via `compdef` and `_arguments`, **hook system compatibility** for `precmd`, `preexec`, and `chpwd` hooks, and **lazy loading compatibility** to avoid penalizing shell startup time. The configuration should enable generating proper zsh completion functions and shell aliases without requiring users to understand the underlying complexity.

The modern completion architecture uses `zstyle` for fine-grained configuration:

```zsh
zstyle ':completion:*:copilot:*' menu select
zstyle ':completion:*:copilot:*' group-name ''
zstyle ':completion:*:copilot:*:descriptions' format '%F{green}-- %d --%f'
```

A master.json should provide options that map to these zstyle patterns, allowing users to customize completion behavior through JSON rather than learning zsh internals.

## Configuration file design should follow the TypeScript/ESLint model

Analysis of successful CLI configuration systems reveals several critical patterns. **TypeScript's tsconfig.json** demonstrates effective inheritance with its `extends` property, allowing base configurations to be shared and selectively overridden. **ESLint's flat config** (introduced in ESLint 9) shows how array-based cascading enables file-pattern-specific rules. **Prettier** proves that sensible defaults with minimal configuration can maximize usability.

The optimal master.json structure should combine these approaches:

```json
{
  "$schema": "https://schemas.github.com/copilot/master.v1.json",
  "extends": "@github/copilot-config-recommended",
  "model": {
    "default": "claude-sonnet-4",
    "fallback": "gpt-4o",
    "temperature": 0.7
  },
  "shell": {
    "type": "auto",
    "completions": true,
    "aliases": {
      "??": "suggest --type shell",
      "git?": "suggest --type git",
      "explain": "explain"
    }
  },
  "tools": {
    "defaults": "prompt",
    "allow": ["shell(git *)", "read", "github"],
    "deny": ["shell(rm -rf)", "shell(sudo *)"]
  },
  "mcp": {
    "servers": {}
  },
  "agents": {
    "path": "~/.copilot/agents",
    "default": null
  },
  "overrides": [
    {
      "directories": ["~/work/**"],
      "tools": { "allow": ["shell(docker *)"] }
    }
  ]
}
```

The **`$schema`** property enables IDE autocompletion and validation. The **`extends`** field supports configuration inheritance. The **`overrides`** array enables directory-specific rules following the Prettier pattern.

## Tool permission patterns require careful hierarchical design

The new Copilot CLI introduces sophisticated tool permissions through `--allow-tool` and `--deny-tool` flags. A master.json should systematize these with **pattern matching**, **hierarchical permissions**, and **context-aware defaults**.

Analysis of Amazon Q CLI's similar system reveals effective permission patterns:

```json
{
  "tools": {
    "shell": {
      "mode": "prompt",
      "allow": [
        "git *",
        "npm install",
        "docker build",
        "docker run --rm *"
      ],
      "deny": [
        "rm -rf *",
        "sudo *",
        "curl * | sh",
        "chmod 777 *"
      ]
    },
    "filesystem": {
      "read": { "allow": ["**/*"], "deny": ["**/.env", "**/secrets/**"] },
      "write": { "allow": ["./src/**", "./docs/**"], "deny": ["./node_modules/**"] }
    },
    "mcp": {
      "github": { "mode": "allow" },
      "custom-server": { "mode": "prompt" }
    }
  }
}
```

The **`mode`** property per tool category enables global defaults (`"allow"`, `"deny"`, or `"prompt"`), while specific patterns provide fine-grained control. This mirrors the security model users expect from modern developer tools.

## Shell integration configuration enables seamless zsh workflows

Research into Shell-GPT, aichat, and Butterfish reveals that successful AI-shell integration requires **context injection**, **output handling options**, and **session persistence**. A master.json should configure these holistically.

Context injection determines what information the AI receives:

```json
{
  "context": {
    "inject": {
      "cwd": true,
      "os": true,
      "shell": "auto",
      "git": {
        "branch": true,
        "status": false,
        "diff": false
      },
      "history": {
        "enabled": false,
        "lines": 10
      },
      "environment": {
        "include": ["NODE_ENV", "PATH"],
        "exclude": ["*_KEY", "*_SECRET", "*_TOKEN"]
      }
    }
  }
}
```

The explicit environment variable patterns prevent accidental secret exposure while allowing useful context like `NODE_ENV` to inform suggestions.

Output handling should support modern terminal capabilities:

```json
{
  "output": {
    "streaming": true,
    "markdown": {
      "enabled": true,
      "theme": "github-dark"
    },
    "codeBlocks": {
      "highlight": true,
      "theme": "one-dark"
    },
    "commands": {
      "workflow": "prompt",
      "clipboard": true,
      "historyIntegration": true
    }
  }
}
```

The **`commands.workflow`** option enables Shell-GPT's effective `[E]xecute/[D]escribe/[A]bort` pattern, while **`historyIntegration`** ensures executed commands appear in shell history for discoverability.

## MCP server configuration extends Copilot's capabilities

The Model Context Protocol represents Copilot CLI's primary extensibility mechanism. A master.json should support both simple and complex MCP configurations:

```json
{
  "mcp": {
    "discovery": {
      "auto": true,
      "paths": ["~/.copilot/mcp-servers", "./.mcp"]
    },
    "servers": {
      "github": {
        "builtin": true,
        "enabled": true
      },
      "database": {
        "type": "stdio",
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-postgres"],
        "env": {
          "DATABASE_URL": "${DATABASE_URL}"
        }
      },
      "figma": {
        "type": "sse",
        "url": "http://localhost:3845/sse"
      }
    },
    "defaults": {
      "timeout": 30000,
      "retries": 3
    }
  }
}
```

Supporting **environment variable interpolation** (`${DATABASE_URL}`) follows aichat's pattern and enables secure credential handling. The **discovery paths** option allows automatic MCP server detection, reducing configuration overhead.

## Custom agents require structured definition patterns

The new Copilot CLI supports custom agents in `~/.copilot/agents/` and repository-local `.github/agents/`. A master.json should enable agent configuration without duplicating the markdown-based agent definition:

```json
{
  "agents": {
    "paths": [
      "~/.copilot/agents",
      "./.github/agents",
      "${XDG_CONFIG_HOME}/copilot/agents"
    ],
    "default": null,
    "shortcuts": {
      "code": "code-review-agent",
      "docs": "documentation-agent",
      "test": "test-generator-agent"
    },
    "permissions": {
      "code-review-agent": {
        "tools": { "allow": ["read", "github"] }
      }
    }
  }
}
```

The **shortcuts** enable quick agent invocation, while **per-agent permissions** provide security boundaries for different agent capabilities.

## Session and history management enhances continuity

AI CLI tools increasingly support session persistence for continued conversations. Shell-GPT and aichat both demonstrate the value of named sessions and conversation compression:

```json
{
  "sessions": {
    "persistence": true,
    "path": "${XDG_STATE_HOME}/copilot/sessions",
    "compression": {
      "enabled": true,
      "threshold": 4000
    },
    "retention": {
      "maxSessions": 50,
      "maxAge": "30d"
    },
    "autoResume": false
  }
}
```

The **compression threshold** triggers automatic context summarization when conversations exceed token limits, following aichat's `compress_threshold` pattern.

## XDG compliance ensures cross-platform consistency

Modern CLI tools increasingly follow the XDG Base Directory Specification. A master.json system should respect these conventions:

```json
{
  "paths": {
    "config": "${XDG_CONFIG_HOME}/copilot",
    "data": "${XDG_DATA_HOME}/copilot",
    "cache": "${XDG_CACHE_HOME}/copilot",
    "state": "${XDG_STATE_HOME}/copilot"
  }
}
```

This separates concerns appropriately: configuration in `config`, persistent data (sessions, agents) in `data`, temporary caches in `cache`, and runtime state in `state`.

## Recommended master.json structure synthesizes all patterns

Combining insights from all research areas, the optimal master.json schema should include these top-level sections:

- **`$schema`** — Enables validation and IDE support
- **`extends`** — Configuration inheritance
- **`model`** — AI model selection and parameters
- **`shell`** — Shell type, completions, aliases, hooks
- **`tools`** — Permission system with allow/deny patterns
- **`context`** — What environmental information to inject
- **`output`** — Streaming, formatting, syntax highlighting
- **`mcp`** — MCP server configurations
- **`agents`** — Custom agent paths and shortcuts
- **`sessions`** — Persistence and history management
- **`paths`** — XDG-compliant directory structure
- **`overrides`** — Directory/project-specific settings

The configuration should support **JSON5** (comments, trailing commas) for better developer experience, and provide a companion **JSON Schema** for validation. Default values should follow Prettier's philosophy of sensible defaults requiring minimal configuration—users should only need to specify what they want to change.

## Conclusion

Designing a comprehensive master.json for GitHub Copilot CLI requires balancing **power with usability**, **security with convenience**, and **flexibility with sensible defaults**. The new agentic architecture demands more sophisticated configuration than the deprecated gh-copilot extension, but modern CLI configuration patterns from TypeScript, ESLint, and AI tools like aichat provide proven models to follow.

Key design principles that emerge from this research: support configuration inheritance to enable shared team settings; implement hierarchical tool permissions with pattern matching; provide XDG-compliant path defaults; enable MCP extensibility with environment variable interpolation; configure shell integration through structured JSON rather than requiring zsh expertise; and implement the override pattern for project-specific customization. Following these patterns will create a configuration system that scales from simple single-user setups to complex enterprise deployments.