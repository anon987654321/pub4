# Implementing Unix Screen-Like Workflows for Universal LLM Framework Loading

**Universal master.yml injection is achievable through a layered architecture combining shell wrappers, API proxies, and IDE-specific configurations.** Screen-like session management requires adapting persistent process patterns to stateless LLM APIs—a fundamental shift that demands checkpoint-based state persistence rather than true process continuity. The most practical approach combines LiteLLM as a universal gateway with LangGraph-style checkpointing for session management, while leveraging tool-specific configuration files (`.github/copilot-instructions.md`, `.cursor/rules/`, `.continue/config.yaml`) for IDE integration.

## Universal injection requires multiple coordinated layers

No single solution provides true universal injection across all LLM interfaces. Instead, you need a **multi-layer architecture** targeting each interface type:

**Shell wrapper pattern (CLI tools):** Create functions in `.bashrc`/`.zshrc` that prepend master.yml to every call:

```bash
MASTER_PROMPT="$HOME/.config/llm/master.yml"

# Wrapper for Simon Willison's llm CLI
llm() {
    if [[ -f "$MASTER_PROMPT" ]]; then
        command llm -s "$(cat $MASTER_PROMPT)" "$@"
    else
        command llm "$@"
    fi
}

# Universal wrapper for any API call
ai_query() {
    local system_prompt=$(cat "$MASTER_PROMPT")
    # Route to appropriate provider
}
```

**LiteLLM proxy (API standardization):** LiteLLM provides a unified gateway supporting 100+ LLM providers with OpenAI-compatible endpoints—the most powerful approach for universal API injection:

```yaml
# litellm_config.yaml
model_list:
  - model_name: gpt-4
    litellm_params:
      model: gpt-4
      api_key: os.environ/OPENAI_API_KEY
  - model_name: claude
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

litellm_settings:
  default_system_message: |
    [Your master.yml content here]
```

All clients then point to `http://localhost:4000`, receiving the injected system prompt automatically regardless of which model they request.

**IDE-specific configurations** require separate files per tool:

| Tool | Configuration Location | Format |
|------|----------------------|--------|
| GitHub Copilot | `.github/copilot-instructions.md` | Markdown |
| Cursor | `.cursor/rules/*.mdc` | MDC (YAML frontmatter + Markdown) |
| Continue.dev | `~/.continue/config.yaml` | YAML with `rules:` section |
| Cody | `.vscode/cody.json` | JSON with custom commands |

The **Ruler** tool provides unified rule management, auto-generating tool-specific files from a single `.ruler/AGENTS.md` source.

## Screen-like workflows face fundamental architectural differences

Unix screen/tmux maintain **persistent processes**—your shell continues running in the background when you detach. LLM APIs are **stateless by design**: every API call starts fresh with no memory of previous interactions. This creates three critical challenges:

**Context window limits vs unlimited shell history:** Shell scrollback is effectively unlimited (**10,000+ lines configurable**), while LLMs have hard token limits (Claude **200K**, GPT-4.1 **128K**, Gemini **1M tokens**). Research from Chroma demonstrates that performance degrades with longer context even on simple tasks—the "lost in the middle" phenomenon where models struggle to retrieve information from the middle of long contexts.

**Token cost of full context restoration:** Restoring a **100K token conversation costs $0.10-$1.00+** per restore. tmux-resurrect restoration costs nothing beyond disk I/O. This economic pressure drives toward **summarization over full replay**.

**No true process continuity:** LLMs cannot truly "pause" mid-computation. Every interaction is a new request, and tool state (file handles, network connections) doesn't persist between calls.

Despite these differences, the **metaphor remains valuable**. Here's how screen concepts translate:

| tmux/screen Concept | LLM Implementation | Notes |
|---------------------|-------------------|-------|
| `tmux new -s name` | `create_session(name, system_prompt)` | Initialize with master.yml |
| `tmux detach` | `checkpoint = serialize(messages, state)` | Save to storage |
| `tmux attach -t name` | `messages = deserialize(checkpoint)` | Reload context |
| `tmux ls` | `list_sessions()` | Return metadata, token counts |
| New window (`Ctrl-a c`) | `fork_session(parent_id)` | Create branch for parallel tasks |
| `capture-pane` | `summarize_conversation()` | Generate compressed context |

**Claude Code provides the most mature screen-like implementation today:**
- `claude --continue`: Resume most recent session (like `screen -r`)
- `claude --resume [id]`: Resume specific session (like `screen -r name`)
- `claude --resume`: Interactive session picker (like `screen -ls` + select)
- **CLAUDE.md**: Persistent project memory that survives across sessions

## LangGraph checkpointing offers production-ready state management

Among frameworks studied (LangChain, AutoGPT, BabyAGI, CrewAI, Semantic Kernel), **LangGraph provides the most sophisticated checkpoint system**. Its architecture stores complete graph state at every node execution:

```python
class Checkpoint(TypedDict):
    v: int                          # Schema version
    id: str                         # Monotonically increasing ID
    ts: str                         # ISO 8601 timestamp
    channel_values: dict[str, Any]  # Serialized state
    channel_versions: ChannelVersions
    versions_seen: dict[str, ChannelVersions]
```

**Thread-based isolation** mirrors screen's session concept:

```python
# Each task gets a unique thread_id
config = {"configurable": {"thread_id": "project_auth_v2"}}
result = graph.invoke(input_data, config)

# Resume from specific checkpoint (time travel)
resume_config = {
    "configurable": {
        "thread_id": "1",
        "checkpoint_id": "1ef4f797-8335-6428-8001-8a1503f9b875"
    }
}
graph.invoke(input, resume_config)
```

**Storage backends** scale from development to production:

| Backend | Use Case | Recommendation |
|---------|----------|----------------|
| `InMemorySaver` | Development/testing | Quick prototyping |
| `SqliteSaver` | Local workflows | Single-user CLI tools |
| `PostgresSaver` | Production | Multi-user, high availability |
| `DynamoDBSaver` | AWS cloud-native | Serverless architectures |

## Optimal session state schema combines multiple formats

After analyzing ChatGPT exports, LangGraph checkpoints, and open-source chat UIs, the recommended architecture uses **SQLite for persistence, JSON for exports, YAML for configuration**:

```typescript
interface Session {
  // Identity
  id: UUID;
  name: string;  // User-assigned label
  thread_id: string;
  parent_session?: UUID;  // For forked sessions
  
  // Timestamps
  created_at: ISO8601;
  updated_at: ISO8601;
  
  // Provider info
  provider: "openai" | "anthropic" | "google";
  model: string;
  
  // Core data
  system_prompt: string;  // master.yml content
  messages: Message[];
  
  // Checkpoints for resume
  checkpoints: {
    id: string;
    message_index: number;
    summary: string;
    token_count: number;
    created_at: ISO8601;
  }[];
  
  // Metrics
  token_usage: {
    input: number;
    output: number;
    estimated_cost_usd: number;
  };
}
```

**Directory structure** following XDG conventions:

```
~/.local/share/llm-sessions/     # Persistent data
├── sessions.db                   # SQLite (LangGraph-compatible)
├── exports/                      # JSON exports
└── summaries/                    # Compressed context

~/.config/llm-sessions/          # Configuration
├── master.yml                    # Your framework
├── personas/                     # Role definitions
└── config.yaml                   # Tool settings

.sessions/                        # Project-local (git-ignored)
├── active.json                   # Current session
└── checkpoints/                  # Named save points
```

## Cross-provider compatibility requires abstraction layers

**LiteLLM** provides the most comprehensive cross-provider abstraction:

```python
from litellm import completion, token_counter

# Unified interface across providers
response = completion(
    model="claude-3-5-sonnet",  # or "gpt-4o", "gemini/gemini-2.0-flash"
    messages=[{"role": "user", "content": "Hello"}]
)

# Cross-provider token counting
tokens = token_counter(model="claude-3-5-sonnet", messages=messages)
```

**Key compatibility challenges:**

- **JSON Schema differences:** OpenAI and Gemini use non-standard schemas for tool calling
- **Tool calling formats:** Varies significantly between providers—MCP (Model Context Protocol) emerging as standardization layer
- **Context window sizes:** Require adaptive truncation strategies
- **Response formats:** Use Pydantic output validation for consistency

## Recommended implementation architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        master.yml                                │
│                  (~/.config/llm/master.yml)                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ Shell Wrappers│   │ LiteLLM Proxy │   │ IDE Configs   │
│ (CLI tools)   │   │ (API gateway) │   │ (.cursor/,    │
│               │   │               │   │  .github/)    │
└───────────────┘   └───────────────┘   └───────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Session Manager                               │
│  create() | attach() | detach() | list() | fork() | compact()   │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────┼─────────────────────────────────────┐
│                    Storage Layer                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   SQLite     │  │  Vector DB   │  │    JSON      │          │
│  │ (checkpoints)│  │  (semantic)  │  │  (exports)   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Practical CLI implementation for screen-like commands

Here's a concrete implementation matching your session_management section:

```bash
#!/bin/bash
# llm-screen - Screen-like session management for LLM chats

SESSIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/llm-sessions"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/llm-sessions"
MASTER_YML="$CONFIG_DIR/master.yml"

case "$1" in
    "new"|"screen")
        SESSION_NAME="${2:-$(date +%Y%m%d_%H%M%S)}"
        mkdir -p "$SESSIONS_DIR/active"
        # Initialize with master.yml
        jq -n --arg name "$SESSION_NAME" \
              --arg system "$(cat $MASTER_YML)" \
              '{name: $name, system_prompt: $system, messages: [], created: now}' \
            > "$SESSIONS_DIR/active/$SESSION_NAME.json"
        echo "Created session: $SESSION_NAME"
        ;;
    "attach"|"-r")
        SESSION_NAME="$2"
        # Load and inject into next LLM call
        export LLM_SESSION="$SESSIONS_DIR/active/$SESSION_NAME.json"
        ;;
    "detach")
        # Current session saves automatically on exit
        cp "$LLM_SESSION" "$SESSIONS_DIR/checkpoints/$(basename $LLM_SESSION .json)_$(date +%s).json"
        ;;
    "list"|"-ls")
        ls -la "$SESSIONS_DIR/active/"
        ;;
    "checkpoint")
        CHECKPOINT_NAME="${2:-checkpoint_$(date +%s)}"
        cp "$LLM_SESSION" "$SESSIONS_DIR/checkpoints/${CHECKPOINT_NAME}.json"
        ;;
esac
```

## Key implementation recommendations

**Start with these components in order:**

1. **Create master.yml loader** at `~/.config/llm/master.yml` with your 1190-line framework
2. **Deploy LiteLLM proxy** for universal API injection—this gives you immediate coverage for all API-based tools
3. **Add shell wrappers** in `.bashrc`/`.zshrc` for CLI tools (llm, aichat, shell-gpt)
4. **Configure IDE-specific files** using Ruler or manual setup:
   - `.github/copilot-instructions.md` 
   - `.cursor/rules/master.mdc`
   - `.continuerules`
5. **Implement session manager** using LangGraph's `SqliteSaver` as the persistence backend
6. **Add context compaction** to handle token limits—summarize older messages while preserving key decisions

**Critical design decisions:**

- Use **thread_id** consistently across tools for session isolation
- Store **checkpoints with TTL** to prevent unbounded database growth
- Implement **sliding window + summary** for context management: keep last N messages verbatim, compress older content
- Design checkpoint schema with **version fields** for future migration support
- Use **LiteLLM's token_counter** for cross-provider token estimation before hitting context limits

The screen metaphor provides excellent UX for LLM session management, but remember: you're building an **approximation of continuity** through careful state serialization, not true process persistence. Design your checkpoint granularity and summarization strategies accordingly.