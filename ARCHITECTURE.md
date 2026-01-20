# Convergence CLI - Enhanced Architecture

## Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Convergence CLI v∞.15.2                     │
│                         (cli.rb - Main)                          │
└────────────┬──────────────────────────────────────┬──────────────┘
             │                                      │
             │                                      │
    ┌────────▼────────┐                  ┌─────────▼──────────┐
    │   EXISTING      │                  │   NEW COMPONENTS   │
    │   COMPONENTS    │                  │   (This PR)        │
    └────────┬────────┘                  └─────────┬──────────┘
             │                                      │
             │                                      │
    ┌────────▼────────────────┐          ┌─────────▼────────────────┐
    │ • WebChat (basic)       │          │ • WebChatClient          │
    │ • APIClient (Anthropic) │          │ • RAGPipeline            │
    │ • RAG (basic)           │          │ • ToolRegistry           │
    │ • Tools (basic)         │          │ • Assistant              │
    │ • UI/Log modules        │          │ • SandboxedFileTool      │
    │ • MasterConfig          │          │                          │
    └─────────────────────────┘          └──────────────────────────┘
```

## 1. cli_webchat.rb - Universal Free LLM Browser Client

```
┌─────────────────────────────────────────────────────────────────┐
│                      WebChatClient                               │
├─────────────────────────────────────────────────────────────────┤
│  State Machine:                                                  │
│  ┌──────┐  connect   ┌──────────┐  send_message  ┌──────────┐  │
│  │READY │────────────▶│CONNECTING│───────────────▶│WAITING   │  │
│  └──────┘            └──────────┘                 │RESPONSE  │  │
│                                                    └────┬─────┘  │
│                                                         │        │
│                      ┌──────────┐                      │        │
│         ┌────────────│STREAMING │◀─────────────────────┘        │
│         │            └────┬─────┘                               │
│         │                 │                                     │
│         ▼                 ▼                                     │
│  ┌──────────┐      ┌──────────┐                                │
│  │COMPLETED │      │  FAILED  │                                │
│  └──────────┘      └──────────┘                                │
├─────────────────────────────────────────────────────────────────┤
│  Providers:                                                      │
│  • DuckDuckGo AI (unlimited)  • HuggingChat (50/day)           │
│  • Perplexity (20/day)        • You.com (30/day)               │
│  • Poe (100/day)                                               │
├─────────────────────────────────────────────────────────────────┤
│  Features:                                                       │
│  • Ferrum stealth mode (anti-detection)                        │
│  • Provider rotation on rate limit                             │
│  • Session persistence (cookies)                               │
│  • Streaming callbacks                                         │
│  • Screenshot capture                                          │
└─────────────────────────────────────────────────────────────────┘
```

## 2. cli_rag.rb - Production RAG Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                       RAGPipeline                                │
├─────────────────────────────────────────────────────────────────┤
│  INDEXING PIPELINE:                                              │
│                                                                  │
│  Documents → Chunker → Embedder → Vector DB → UMAP Training     │
│                 │                      │                         │
│                 │                      └──→ Reduced Embeddings   │
│                 │                                                │
│          ┌──────▼───────┐                                       │
│          │ Baran        │  Smart chunking:                      │
│          │ Recursive    │  • Respects paragraphs               │
│          │ Splitter     │  • Respects sentences                │
│          └──────────────┘  • Configurable overlap              │
├─────────────────────────────────────────────────────────────────┤
│  QUERY PIPELINE:                                                 │
│                                                                  │
│  Query → Query Rewriter → Multi-Query Search                    │
│             │                      │                             │
│             └──→ [Q1, Q2, Q3]     │                             │
│                      │             │                             │
│                      └──────→ Search Each Query                 │
│                                    │                             │
│                      ┌─────────────▼────────────┐               │
│                      │ RRF Fusion               │               │
│                      │ (Reciprocal Rank Fusion) │               │
│                      └─────────┬────────────────┘               │
│                                │                                 │
│                      ┌─────────▼────────────┐                   │
│                      │ Cross-Encoder        │                   │
│                      │ Reranker             │                   │
│                      └─────────┬────────────┘                   │
│                                │                                 │
│                      ┌─────────▼────────────┐                   │
│                      │ Context Repacker     │                   │
│                      │ (Deduplicate)        │                   │
│                      └─────────┬────────────┘                   │
│                                │                                 │
│                                ▼                                 │
│                          LLM Context                             │
├─────────────────────────────────────────────────────────────────┤
│  Degradation Levels:                                             │
│  • :full    → Semantic search (embeddings + vector DB)         │
│  • :keyword → TF-IDF keyword search (no embeddings)            │
│  • :simple  → Substring matching (no dependencies)             │
└─────────────────────────────────────────────────────────────────┘
```

## 3. cli_tools.rb - Enhanced Tool Execution System

```
┌─────────────────────────────────────────────────────────────────┐
│                      ToolRegistry                                │
├─────────────────────────────────────────────────────────────────┤
│  State Machine:                                                  │
│  ┌──────┐  execute  ┌─────────────┐  tool_calls  ┌──────────┐  │
│  │READY │───────────▶│IN_PROGRESS  │─────────────▶│REQUIRES  │  │
│  └──┬───┘           └─────────────┘              │ACTION    │  │
│     │                                             └────┬─────┘  │
│     │                                                  │        │
│     │  ┌───────────┐                 approve_tools    │        │
│     └──│COMPLETED  │◀─────────────────────────────────┘        │
│        └───────────┘                                            │
│             │                                                    │
│             ▼                                                    │
│        ┌───────────┐                                            │
│        │  FAILED   │                                            │
│        └───────────┘                                            │
├─────────────────────────────────────────────────────────────────┤
│  Tools:                                                          │
│  ┌──────────────────┬─────────────────────────────────────┐    │
│  │ EnhancedShellTool│ • Banned tool checking             │    │
│  │                  │ • Dangerous pattern blocking        │    │
│  │                  │ • Timeout support                   │    │
│  ├──────────────────┼─────────────────────────────────────┤    │
│  │ ReadFileTool     │ • Sandboxed reading                │    │
│  │                  │ • Line numbers option               │    │
│  │                  │ • Line range support                │    │
│  ├──────────────────┼─────────────────────────────────────┤    │
│  │ WriteFileTool    │ • Sandboxed writing                │    │
│  │                  │ • Append mode                       │    │
│  │                  │ • Auto-create dirs                  │    │
│  ├──────────────────┼─────────────────────────────────────┤    │
│  │ ListFilesTool    │ • Recursive option                 │    │
│  │                  │ • Pattern filtering                 │    │
│  ├──────────────────┼─────────────────────────────────────┤    │
│  │ SearchFilesTool  │ • Content search                   │    │
│  │                  │ • Case sensitivity option           │    │
│  │                  │ • Performance optimized             │    │
│  └──────────────────┴─────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│  SandboxedFileTool Mixin:                                       │
│                                                                  │
│  ┌────────────┐         ┌──────────────┐                       │
│  │ User Input │────────▶│enforce_      │                       │
│  │ Path       │         │sandbox!()    │                       │
│  └────────────┘         └──────┬───────┘                       │
│                                │                                 │
│                         Check if path                            │
│                         starts with                              │
│                         @base_path                               │
│                                │                                 │
│                    ┌───────────▼───────────┐                    │
│                    │ YES          │   NO   │                    │
│                    │              │        │                    │
│              ┌─────▼─────┐  ┌────▼────────▼───┐                │
│              │  ALLOW    │  │ SecurityError   │                │
│              │  ACCESS   │  │ Raised          │                │
│              └───────────┘  └─────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

## Integration Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        cli.rb (Main)                             │
└────┬─────────────────────────────────────────────────┬──────────┘
     │                                                  │
     │ require_relative                                │
     │                                                  │
┌────▼────────────┐  ┌───────────────┐  ┌─────────────▼────────┐
│ cli_webchat.rb  │  │ cli_rag.rb    │  │ cli_tools.rb         │
└────┬────────────┘  └───┬───────────┘  └─────────┬────────────┘
     │                   │                         │
     │ @client =         │ @rag =                 │ @tools =
     │ WebChatClient.new │ RAGPipeline.new        │ ToolRegistry.new
     │                   │                         │
     │                   │                         │
┌────▼───────────────────▼─────────────────────────▼────────────┐
│                   Convergence Module                           │
│                                                                │
│  • Shared namespace                                           │
│  • Common patterns                                            │
│  • Consistent error handling                                  │
│  • Master.yml integration                                     │
└────────────────────────────────────────────────────────────────┘
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Security Layers                               │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Master.yml Constraints                                │
│  • Banned tools list                                            │
│  • Alternative suggestions                                      │
│  • Global policy enforcement                                    │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Pattern Blocking                                      │
│  • Dangerous command patterns                                   │
│  • rm -rf / protection                                          │
│  • Pipe to shell blocking                                       │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Path Sandboxing                                       │
│  • Enforce base_path restriction                                │
│  • Block path traversal (../)                                   │
│  • Validate before every operation                              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: OpenBSD Pledge/Unveil                                 │
│  • System-level constraints                                     │
│  • Capability limiting                                          │
│  • File system visibility control                               │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow Examples

### Example 1: WebChat with Provider Rotation

```
User Query
    │
    ▼
WebChatClient
    │
    ├──→ Try DuckDuckGo
    │    │
    │    ├──→ Rate Limited ✗
    │    │
    │    └──→ Rotate to HuggingChat
    │         │
    │         └──→ Success ✓
    │              │
    │              ▼
    │         Stream Response
    │              │
    │              └──→ Callback: on_streaming(text)
    │                   │
    │                   ▼
    │         Final Response
    ▼
User Receives Answer
```

### Example 2: RAG with Multi-Query Search

```
User Query: "How do I use CLI tools?"
    │
    ▼
Query Rewriter
    │
    ├──→ Q1: "How do I use CLI tools?"
    ├──→ Q2: "What are CLI tool commands?"
    └──→ Q3: "CLI tools usage guide"
         │
         ▼
    Parallel Search
         │
    ├────┴────┬────────┐
    │         │        │
    R1[...]   R2[...]  R3[...]
    │         │        │
    └────┬────┴────────┘
         │
         ▼
    RRF Fusion
    (Combine + Score)
         │
         ▼
    Reranker
    (Position-aware)
         │
         ▼
    Context Repacker
    (Deduplicate)
         │
         ▼
    Augmented Query
         │
         ▼
    LLM Response
```

### Example 3: Tool Execution with Sandboxing

```
LLM Request: read_file("/etc/passwd")
    │
    ▼
ToolRegistry
    │
    ▼
ReadFileTool.execute
    │
    ▼
enforce_sandbox!("/etc/passwd")
    │
    ├──→ Check: starts with base_path?
    │    │
    │    └──→ NO ✗
    │         │
    │         ▼
    │    SecurityError
    │         │
    │         ▼
    │    Return: {error: "Access denied"}
    │
    ▼
LLM Receives Error
    │
    ▼
LLM Requests: read_file("./config.yml")
    │
    ▼
enforce_sandbox!("./config.yml")
    │
    └──→ YES ✓
         │
         ▼
    File Read Successful
         │
         ▼
    Return: {content: "..."}
```

## Performance Characteristics

```
Component         | Operation      | Latency      | Memory
─────────────────┼───────────────┼──────────────┼─────────
WebChatClient    | send_message   | 2-10s        | ~100MB
                 | screenshot     | <1s          | ~5MB
─────────────────┼───────────────┼──────────────┼─────────
RAGPipeline      | ingest (simple)| 1ms/chunk    | 1KB/chunk
                 | ingest (embed) | 10ms/chunk   | 1.5KB/chunk
                 | search (kw)    | <100ms       | -
                 | search (sem)   | <500ms       | -
─────────────────┼───────────────┼──────────────┼─────────
ToolRegistry     | shell          | <1s          | -
                 | read_file      | <100ms       | variable
                 | search_files   | 1-5s         | variable
                 | sandbox_check  | <1ms         | -
```

## Dependencies Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                      stdlib (always available)                   │
│  json, yaml, fileutils, open3, timeout, digest, set            │
└────────────────────┬────────────────────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
    ┌────▼────┐ ┌───▼────┐ ┌───▼────┐
    │ ferrum  │ │ baran  │ │neighbor│
    │(WebChat)│ │  (RAG) │ │  (RAG) │
    └────┬────┘ └───┬────┘ └───┬────┘
         │          │           │
    ┌────▼─────────┐│           │
    │ Chromium/    ││           │
    │ Chrome       ││           │
    │ Browser      ││           │
    └──────────────┘│           │
         │          │           │
         └──────────┴───────────┘
                    │
         ┌──────────▼──────────┐
         │  Optional Services  │
         │  • OpenAI API       │
         │  • Ollama (local)   │
         └─────────────────────┘
```

## File Structure

```
pub4/
├── cli.rb                      # Main CLI (existing)
├── cli_webchat.rb              # New: WebChat component
├── cli_rag.rb                  # New: RAG component
├── cli_tools.rb                # New: Tools component
├── cli_integration_example.rb  # New: Integration examples
├── CLI_COMPONENTS_README.md    # New: Documentation
├── IMPLEMENTATION_SUMMARY.md   # New: Implementation summary
├── ARCHITECTURE.md             # New: This file
└── master.yml                  # Existing: Configuration
```

## Key Design Patterns

1. **State Machine Pattern** - WebChat, Tools, Assistant
2. **Strategy Pattern** - RAG degradation levels
3. **Mixin Pattern** - SandboxedFileTool
4. **Callback Pattern** - Streaming, tool execution
5. **Factory Pattern** - Tool registry
6. **Lazy Initialization** - Embedding provider detection
7. **Graceful Degradation** - All components
8. **Sandbox Pattern** - File operations

## Future Enhancements

Potential areas for extension:
- Additional LLM providers for WebChat
- More embedding providers for RAG
- Additional tools for ToolRegistry
- Advanced reranking models
- Vector database backends
- Distributed search capabilities
