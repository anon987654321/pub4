# AI3 → Aight.rb Restoration & Refactoring Plan
**Master.json v225.0.0 Compliant**

**Date**: 2025-09-30
---

## Current State Analysis

### Existing Structure (ai3/)
```
ai3/
├── README.md                  # AI^3 CLI documentation

├── crc.rb                     # Claude Ruby CLI (1570 lines)

├── lib/                       # Core libraries

│   ├── autonomous_behavior.rb

│   ├── assistant_orchestrator.rb

│   ├── context_manager.rb

│   ├── command_handler.rb

│   ├── enhanced_model_architecture.rb

│   ├── efficient_data_retrieval.rb

│   ├── error_handling.rb

│   ├── feedback_manager.rb

│   ├── filesystem_tool.rb

│   ├── interactive_session.rb

│   ├── memory_manager.rb

│   ├── prompt_manager.rb

│   ├── query_cache.rb

│   ├── rag_engine.rb

│   ├── rate_limit_tracker.rb

│   ├── session_manager.rb

│   ├── ui.rb

│   ├── universal_scraper.rb

│   └── weaviate.rb

├── assistants/                # 15 specialized assistants

│   ├── README.md

│   ├── web_developer.rb

│   ├── trader.rb

│   ├── sys_admin.rb

│   ├── sound_mastering.rb

│   ├── seo.rb

│   ├── rocket_scientist.rb

│   ├── real_estate.rb

│   ├── propulsion_engineer.rb

│   ├── personal_assistant.rb

│   ├── openbsd_driver_translator.rb

│   ├── offensive_operations.rb

│   ├── medical_doctor.rb

│   ├── material_science.rb

│   ├── lawyer.rb

│   ├── healthcare.rb

│   ├── hacker.rb

│   ├── architect.rb

│   └── advanced_propulsion.rb

├── chatbots/                  # Social media automation

│   ├── README.md

│   ├── chatbot.rb

│   ├── influencer.rb

│   ├── config.json

│   ├── prompts.json

│   └── modules/

│       ├── snapchat.rb

│       ├── reddit.rb

│       ├── onlyfans.rb

│       ├── discord.rb

│       └── 4chan.rb

└── assistants/multimedia/

    └── replicate.rb           # AI media generation

```

### GitHub Backups Available

**__OLD_BACKUPS** (August 2024):

- `egpt_20240804.tgz` - Original egpt system
- `egpt_20240806.tgz` - Later egpt backup
- `openbsd_*.tgz` - System backups

- `rails_*.tgz` - Rails projects

- `master_framework_*.rb` - Framework files

### Features to Preserve

1. **Multi-LLM Support**: Grok, Claude, OpenAI, Ollama

2. **RAG Engine**: Weaviate integration
3. **15 Specialized Assistants**: Domain experts
4. **Universal Scraper**: Ferrum-based with screenshots

5. **Multimedia**: Replicate.com integration

6. **FileUtils**: CLI access with doas/root

7. **Security**: OpenBSD pledge/unveil, encryption

8. **Chatbots**: Snapchat, Reddit, OnlyFans, Discord, 4chan

9. **CRC**: Claude Ruby CLI with cognitive tracking

10. **Knowledge Store**: File-based RAG

---

## Renaming Strategy: AI3 → Aight.rb

### Name Rationale
- **Aight** = "AI" + "right" (Gen-Z slang for "alright")
- **`.rb`** = Ruby file extension, also Ruby-centric branding
- Memorable, searchable, unique

### Files to Rename

**Main entry point**:

- `ai3.rb` → `aight.rb`
**Directory**:
- `ai3/` → `aight/`

**Config**:
- `~/.ai3_keys` → `~/.aight_keys`

- `~/.config/ai3/` → `~/.config/aight/`
**Module namespace**:

- `AI3::` → `Aight::` (Ruby modules)

**Documentation references**:
- All README files

- Comments
- Configuration files

---

## Master.json v225.0.0 Compliance

### Principles to Apply
1. **Evidence-based**: Validate all integrations before use
2. **Reversible**: Git-tracked, backup original
3. **Minimal**: Remove unused code, consolidate
4. **Explicit**: Clear naming, no implicit behavior

5. **Platform-aware**: zsh scripts, OpenBSD native

6. **Secure**: Leverage OpenBSD features

### Code Quality Improvements

**Ruby Style**:

- Frozen string literals
- Keyword arguments
- Double quotes

- Two-space indentation

- No trailing whitespace

**Structure**:

- DRY: Extract common patterns

- SOLID: Single responsibility
- YAGNI: Remove speculative features

**Security**:

- Input validation

- API key handling
- Sandboxing (pledge/unveil)

- Rate limiting

---

## Restoration Tasks

### Task 1: Extract egpt Backups
```bash
cd /g/pub/__OLD_BACKUPS
tar -xzf egpt_20240804.tgz -C /tmp/egpt_old

tar -xzf egpt_20240806.tgz -C /tmp/egpt_new

# Compare with current ai3

diff -r /tmp/egpt_new /g/pub/ai3 > /tmp/egpt_diff.txt

```
**Restore if missing**:

- Installation scripts

- Config templates
- Documentation

- Tests (if any)

- Example prompts

- API integration code

### Task 2: Rename ai3 → Aight

**Phase 1: File System**

```bash
cd /g/pub
mv ai3 aight

# Update entry point

mv aight/ai3.rb aight/aight.rb

```
**Phase 2: Code References**

```ruby

# Find all AI3 module references
grep -r "AI3::" aight/

grep -r "ai3" aight/

# Replace module namespace

find aight -name "*.rb" -exec sed -i 's/AI3::/Aight::/g' {} +

find aight -name "*.rb" -exec sed -i 's/ai3/aight/g' {} +
```

**Phase 3: Configuration**

```ruby

# In all Ruby files
CrossPlatformPath.config_directory:

  OLD: File.join(xdg_config, "crc")

  NEW: File.join(xdg_config, "aight")

# Keys file

OLD: ~/.ai3_keys

NEW: ~/.aight_keys or ~/.config/aight/keys.yml
```

**Phase 4: Documentation**

```bash

# Update all README files
sed -i 's/AI\^3/Aight.rb/g' aight/**/*.md

sed -i 's/ai3/aight/g' aight/**/*.md

```

### Task 3: Master.json Compliance

**File by File Refactoring**:

**aight.rb** (main entry):
- [ ] Add frozen_string_literal
- [ ] Explicit requires (no autoload)
- [ ] Keyword arguments throughout

- [ ] Error handling with rescue

- [ ] Logging with structured JSON

- [ ] CLI help with examples

**lib/*.rb**:

- [ ] Module namespace: `Aight::`

- [ ] Class documentation
- [ ] Method visibility (private/protected)

- [ ] Input validation

- [ ] Return value consistency

- [ ] No global variables

- [ ] Thread-safe where needed

**assistants/*.rb**:

- [ ] Base class pattern

- [ ] Shared configuration
- [ ] Consistent interfaces

- [ ] Tool integration

- [ ] Error recovery

- [ ] Logging per assistant

**chatbots/*.rb**:

- [ ] Rate limiting

- [ ] CAPTCHA handling
- [ ] Session persistence

- [ ] Ethical guidelines

- [ ] Content filtering

- [ ] API fallbacks

### Task 4: CRC Integration

**CRC** (Claude Ruby CLI) is excellent - keep it!

**Improvements**:
- [ ] Rename to `aight-crc.rb` or integrate into main
- [ ] Share configuration with main Aight
- [ ] Unified logging

- [ ] Cross-platform path handling (already good!)

- [ ] Add to OpenBSD deployment

### Task 5: OpenBSD Integration

**Add to openbsd.sh**:

```bash
# Install Aight.rb
setup_aight() {

  log "INFO" "Installing Aight.rb..."

  # Install Ruby gems

  gem install langchainrb faraday ferrum weaviate-ruby concurrent-ruby

  # Clone or copy Aight
  if [[ ! -d "/home/ai/aight" ]]; then

    cp -r /path/to/aight /home/ai/aight
    chown -R ai:ai /home/ai/aight

  fi

  # Configure

  doas -u ai /home/ai/aight/install.sh

  # Add to rc.d if daemon mode
  if [[ "$AIGHT_DAEMON" == "true" ]]; then

    cat > /etc/rc.d/aight << 'EOF'
#!/bin/ksh

daemon="/home/ai/aight/aight.rb"

daemon_user="ai"

. /etc/rc.d/rc.subr

rc_bg=YES

rc_cmd $1

EOF

    chmod +x /etc/rc.d/aight

    rcctl enable aight

  fi

  log "INFO" "Aight.rb installed"

}

```
### Task 6: New Features

**1. LangChainRB Integration** (already present - enhance):

- [ ] Vector store abstraction (Weaviate, pgvector, Pinecone)
- [ ] Prompt templates library
- [ ] Chain composition

- [ ] Agent patterns

**2. Replicate.com Multimedia** (already present - enhance):

- [ ] Model caching

- [ ] Queue management
- [ ] Cost tracking

- [ ] Output storage (S3/local)

**3. RAG Engine** (already present - enhance):

- [ ] Document ingestion pipeline

- [ ] Chunking strategies
- [ ] Hybrid search (keyword + vector)

- [ ] Reranking

**4. Chatbot Ethics**:

- [ ] Content policy enforcement

- [ ] Rate limiting per platform
- [ ] User consent tracking

- [ ] GDPR compliance

**5. Assistant Marketplace**:

- [ ] Plugin system for new assistants

- [ ] Config-driven assistant creation
- [ ] Tool composition

### Task 7: Testing

**Add Tests**:

```ruby
# test/aight_test.rb
require "minitest/autorun"

require_relative "../lib/aight"

class AightTest < Minitest::Test

  def test_configuration_load

    config = Aight::Configuration.load
    assert config.is_a?(Hash)

  end

  def test_llm_provider_setup

    config = {"default_model" => "mock"}

    provider = Aight::LLMProvider.new(config, Logger.new($stdout))
    assert provider.available?

  end

end

```

---

## Implementation Plan

### Week 1: Restoration & Renaming
- [ ] Extract egpt backups
- [ ] Compare with current ai3
- [ ] Identify missing critical files

- [ ] Restore missing files

- [ ] Rename ai3 → aight (file system)

- [ ] Update module namespace (AI3 → Aight)

- [ ] Update config paths

- [ ] Update documentation

- [ ] Git commit: "Restore egpt backups and rename to Aight.rb"

### Week 2: Master.json Compliance

- [ ] Run all .rb files through master.json principles

- [ ] frozen_string_literal everywhere
- [ ] Keyword arguments

- [ ] Error handling

- [ ] Input validation

- [ ] Code style (Rubocop)

- [ ] Remove dead code

- [ ] Extract common patterns

- [ ] Git commit per file category

### Week 3: Integration & Enhancement

- [ ] CRC integration with main Aight

- [ ] OpenBSD openbsd.sh integration
- [ ] LangChainRB enhancements

- [ ] Replicate.com enhancements

- [ ] RAG engine improvements

- [ ] Chatbot ethics layer

- [ ] Testing suite

- [ ] Git commits per feature

### Week 4: Documentation & Deployment

- [ ] Comprehensive README

- [ ] API documentation (YARD)
- [ ] Usage examples

- [ ] Configuration guide

- [ ] Deployment guide (OpenBSD)

- [ ] Video tutorial (optional)

- [ ] Release v1.0.0

---

## File Checklist

### Critical Files to Process
**Core** (18 files):
- [ ] aight.rb (main entry)
- [ ] crc.rb (Claude CLI)
- [ ] lib/autonomous_behavior.rb

- [ ] lib/assistant_orchestrator.rb

- [ ] lib/context_manager.rb

- [ ] lib/command_handler.rb

- [ ] lib/enhanced_model_architecture.rb

- [ ] lib/efficient_data_retrieval.rb

- [ ] lib/error_handling.rb

- [ ] lib/feedback_manager.rb

- [ ] lib/filesystem_tool.rb

- [ ] lib/interactive_session.rb

- [ ] lib/memory_manager.rb

- [ ] lib/prompt_manager.rb

- [ ] lib/query_cache.rb

- [ ] lib/rag_engine.rb

- [ ] lib/rate_limit_tracker.rb

- [ ] lib/session_manager.rb

- [ ] lib/ui.rb

- [ ] lib/universal_scraper.rb

- [ ] lib/weaviate.rb

**Assistants** (18 files):

- [ ] assistants/web_developer.rb

- [ ] assistants/trader.rb
- [ ] assistants/sys_admin.rb

- [ ] assistants/sound_mastering.rb

- [ ] assistants/seo.rb

- [ ] assistants/rocket_scientist.rb

- [ ] assistants/real_estate.rb

- [ ] assistants/propulsion_engineer.rb

- [ ] assistants/personal_assistant.rb

- [ ] assistants/openbsd_driver_translator.rb

- [ ] assistants/offensive_operations.rb

- [ ] assistants/medical_doctor.rb

- [ ] assistants/material_science.rb

- [ ] assistants/lawyer.rb

- [ ] assistants/healthcare.rb

- [ ] assistants/hacker.rb

- [ ] assistants/architect.rb

- [ ] assistants/advanced_propulsion.rb

- [ ] assistants/multimedia/replicate.rb

**Chatbots** (7 files):

- [ ] chatbots/chatbot.rb

- [ ] chatbots/influencer.rb
- [ ] chatbots/modules/snapchat.rb

- [ ] chatbots/modules/reddit.rb

- [ ] chatbots/modules/onlyfans.rb

- [ ] chatbots/modules/discord.rb

- [ ] chatbots/modules/4chan.rb

**Total**: 43 Ruby files to refactor

---

## Success Criteria
- [ ] All egpt backups reviewed and critical files restored
- [ ] All references to ai3/egpt renamed to Aight.rb
- [ ] All Ruby files follow master.json v225.0.0 principles
- [ ] Code runs on OpenBSD without errors

- [ ] Integration with openbsd.sh deployment

- [ ] Tests cover core functionality

- [ ] Documentation complete and accurate

- [ ] Git history clean with semantic commits

- [ ] Version 1.0.0 released

---

## Risk Mitigation

**Risk 1**: Breaking changes during rename
**Mitigation**: Git branch, test after each phase, rollback capability
**Risk 2**: Missing features from egpt backups
**Mitigation**: Thorough diff analysis, restore incrementally, test each addition

**Risk 3**: Platform incompatibility (OpenBSD)
**Mitigation**: Test on OpenBSD VM, use base tools only, avoid GNU extensions

**Risk 4**: API breaking changes (LangChainRB, Replicate, etc.)
**Mitigation**: Version pinning, fallback implementations, graceful degradation

---
**Status**: Ready for systematic execution

**Next Action**: Begin Task 1 - Extract and compare egpt backups
