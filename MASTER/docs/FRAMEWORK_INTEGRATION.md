# Framework Integration Guide

This document explains the framework and plugin system integrated into MASTER v52.0+ from the pub, pub2, and pub3 repositories.

## Overview

MASTER includes two complementary systems:

1. **Framework Modules** - Core development workflow and quality enforcement
2. **Plugin Modules** - Domain-specific extensions for specialized use cases

Both systems are automatically loaded via the `MASTER::Framework` and `MASTER::Plugins` namespaces.

---

## Framework Modules

Located in `lib/framework/` with configuration in `lib/config/framework/`

### 1. Behavioral Rules (`behavioral_rules.rb`)

Enforces coding patterns and development habits across the codebase.

**Purpose**: Define and enforce behavioral expectations for code quality

**Key Features**:
- Pattern matching for common anti-patterns
- Habit tracking for developer behavior
- Coding standard enforcement
- Real-time feedback during development

**Configuration**: `lib/config/framework/behavioral_rules.yml`

```yaml
rules:
  - name: "no_god_classes"
    description: "Classes should have single responsibility"
    pattern: "class.*\\n.*def.*\\n" # simplified
    severity: error
    max_methods: 15
    max_lines: 300
```

**Usage**:
```ruby
require 'master'

checker = MASTER::Framework::BehavioralRules.new
violations = checker.scan(file_path)
violations.each { |v| puts v.message }
```

---

### 2. Universal Standards (`universal_standards.rb`)

Cross-language quality rules that apply regardless of tech stack.

**Purpose**: Enforce quality standards that transcend language boundaries

**Key Features**:
- Language-agnostic quality metrics
- Cross-project consistency
- Universal best practices
- Portable quality gates

**Configuration**: `lib/config/framework/universal_standards.yml`

```yaml
standards:
  file_size:
    max_lines: 500
    warning_threshold: 300
  
  function_complexity:
    max_cyclomatic: 10
    max_nesting: 4
  
  naming:
    min_length: 3
    no_abbreviations: true
```

**Usage**:
```ruby
standards = MASTER::Framework::UniversalStandards.new
standards.check_file_size(path) # => { compliant: true/false, lines: 423 }
standards.check_complexity(method) # => { score: 7, compliant: true }
```

---

### 3. Workflow Engine (`workflow_engine.rb`)

8-phase development cycle automation.

**Purpose**: Guide developers through structured workflow phases

**Key Features**:
- 8 defined phases: Plan → Design → Implement → Test → Review → Refactor → Document → Deploy
- Phase transition validation
- Progress tracking
- Checkpoint/rollback support

**Configuration**: `lib/config/framework/workflow_engine.yml`

```yaml
phases:
  - name: plan
    duration_estimate: "30m"
    required_artifacts: ["requirements.md"]
    
  - name: design
    duration_estimate: "1h"
    required_artifacts: ["architecture.md", "api_spec.yml"]
    
  - name: implement
    duration_estimate: "4h"
    gates: ["behavioral_rules", "universal_standards"]
```

**Usage**:
```ruby
workflow = MASTER::Framework::WorkflowEngine.new
workflow.current_phase # => :implement
workflow.advance_to(:test) # Validates phase transition
workflow.artifacts # => ["src/app.rb", "test/app_test.rb"]
```

---

### 4. Quality Gates (`quality_gates.rb`)

Pass/fail criteria for code promotion.

**Purpose**: Prevent low-quality code from advancing through workflow

**Key Features**:
- Configurable gate criteria
- Multi-dimensional quality scoring
- Automated gate enforcement
- Gate override with audit trail

**Configuration**: `lib/config/framework/quality_gates.yml`

```yaml
gates:
  commit:
    - no_failing_tests: true
    - max_violations: 0
    - min_coverage: 80
    
  merge:
    - code_review_approved: true
    - ci_passing: true
    - no_security_issues: true
    
  deploy:
    - all_gates_passed: true
    - performance_benchmarks: true
    - documentation_complete: true
```

**Usage**:
```ruby
gates = MASTER::Framework::QualityGates.new
result = gates.check(:commit)

if result.passed?
  Git.commit(message)
else
  puts "Gates failed: #{result.failures.join(', ')}"
end
```

---

### 5. Copilot Optimization (`copilot_optimization.rb`)

AI assistant tuning and prompt optimization.

**Purpose**: Maximize effectiveness of AI-assisted development

**Key Features**:
- Prompt template management
- Context window optimization
- Response quality scoring
- Cost-aware request batching

**Configuration**: `lib/config/framework/copilot_optimization.yml`

```yaml
optimization:
  context_window: 8192
  temperature: 0.7
  max_tokens: 2048
  
templates:
  refactor:
    system: "You are an expert refactoring assistant..."
    user: "Refactor this code following SOLID principles: {code}"
    
  review:
    system: "You are a senior code reviewer..."
    user: "Review this PR for issues: {diff}"
```

**Usage**:
```ruby
copilot = MASTER::Framework::CopilotOptimization.new
response = copilot.refactor(code, template: :refactor)
copilot.log_metrics # => { tokens: 1250, cost: 0.002, quality_score: 0.89 }
```

---

## Plugin System

Located in `lib/plugins/` with configuration in `lib/config/plugins/`

Plugins extend MASTER for domain-specific use cases.

### 1. Design System (`design_system.rb`)

Tadao Ando design principles for visual systems.

**Purpose**: Apply architectural design principles to software aesthetics

**Key Features**:
- Minimalist design enforcement
- Visual rhythm analysis
- Color palette validation
- Typography consistency

**Configuration**: `lib/config/plugins/design_system.yml`

```yaml
principles:
  - simplicity: "Reduce to essential elements"
  - light: "Emphasize natural light and space"
  - materiality: "Honest use of materials"
  - geometry: "Precise geometric forms"
  
constraints:
  max_colors: 5
  typography_scale: [12, 14, 16, 20, 24, 32]
  spacing_unit: 8
```

**Usage**:
```ruby
design = MASTER::Plugins::DesignSystem.new
design.validate_palette(['#000000', '#FFFFFF', '#333333'])
design.check_typography_scale(font_sizes)
```

---

### 2. Web Development (`web_development.rb`)

Rails/Hotwire patterns and web best practices.

**Purpose**: Enforce modern web development patterns

**Key Features**:
- RESTful routing validation
- Hotwire/Turbo patterns
- Progressive enhancement checks
- Performance budgets

**Configuration**: `lib/config/plugins/web_development.yml`

```yaml
patterns:
  restful_routes: true
  turbo_frames: true
  stimulus_controllers: true
  
performance:
  max_bundle_size: "200kb"
  max_initial_load: "3s"
  lighthouse_score: 90
```

**Usage**:
```ruby
web = MASTER::Plugins::WebDevelopment.new
web.validate_routes(Rails.application.routes)
web.check_bundle_size('app/javascript/bundle.js')
```

---

### 3. Business Strategy (`business_strategy.rb`)

Product/market fit analysis and business validation.

**Purpose**: Align technical decisions with business goals

**Key Features**:
- Feature value scoring
- Market fit assessment
- ROI calculation
- Stakeholder impact analysis

**Configuration**: `lib/config/plugins/business_strategy.yml`

```yaml
metrics:
  - user_value: 0.4
  - business_value: 0.3
  - technical_feasibility: 0.2
  - strategic_alignment: 0.1
  
thresholds:
  min_score: 7.0
  must_have: 8.5
```

**Usage**:
```ruby
strategy = MASTER::Plugins::BusinessStrategy.new
score = strategy.evaluate_feature(
  name: "Real-time collaboration",
  user_value: 9,
  business_value: 8,
  technical_feasibility: 6,
  strategic_alignment: 9
)
# => { score: 8.1, recommendation: "build" }
```

---

### 4. AI Enhancement (`ai_enhancement.rb`)

LLM integration patterns and AI-powered features.

**Purpose**: Standardize AI integration across the system

**Key Features**:
- Prompt management
- Response validation
- Cost tracking
- Model selection strategies

**Configuration**: `lib/config/plugins/ai_enhancement.yml`

```yaml
models:
  smart:
    provider: "anthropic"
    model: "claude-3.5-sonnet"
    temperature: 0.7
    
  fast:
    provider: "openai"
    model: "gpt-4o-mini"
    temperature: 0.3
    
cost_limits:
  per_request: 0.50
  daily: 10.00
  monthly: 200.00
```

**Usage**:
```ruby
ai = MASTER::Plugins::AIEnhancement.new
response = ai.complete(
  prompt: "Explain this code",
  model: :smart,
  max_tokens: 500
)
puts "Cost: $#{response.cost}"
```

---

## Integration Architecture

### Module Loading

Framework and plugins are autoloaded in `lib/master.rb`:

```ruby
module MASTER
  # Framework modules
  module Framework
    autoload :BehavioralRules,     "#{LIB}/framework/behavioral_rules"
    autoload :CopilotOptimization, "#{LIB}/framework/copilot_optimization"
    autoload :QualityGates,        "#{LIB}/framework/quality_gates"
    autoload :UniversalStandards,  "#{LIB}/framework/universal_standards"
    autoload :WorkflowEngine,      "#{LIB}/framework/workflow_engine"
  end

  # Plugin modules
  module Plugins
    autoload :AIEnhancement,     "#{LIB}/plugins/ai_enhancement"
    autoload :BusinessStrategy,  "#{LIB}/plugins/business_strategy"
    autoload :DesignSystem,      "#{LIB}/plugins/design_system"
    autoload :WebDevelopment,    "#{LIB}/plugins/web_development"
  end
end
```

### Configuration Loading

All modules use YAML configuration with mtime caching:

```ruby
class BehavioralRules
  def config
    @config ||= load_config('framework/behavioral_rules.yml')
  end
  
  def load_config(path)
    full_path = File.join(MASTER::ROOT, 'lib/config', path)
    YAML.load_file(full_path)
  end
end
```

---

## CLI Integration

Framework and plugins integrate with the CLI:

```bash
# Check behavioral rules
bin/cli scan --rules behavioral lib/

# Run quality gates
bin/cli gates check --gate commit

# Validate design system
bin/cli design validate app/assets/

# Evaluate business strategy
bin/cli strategy score feature.yml
```

---

## Testing

Each module includes comprehensive tests:

```bash
# Framework tests
ruby test/framework/test_behavioral_rules.rb
ruby test/framework/test_workflow_engine.rb

# Plugin tests
ruby test/plugins/test_design_system.rb
ruby test/plugins/test_ai_enhancement.rb

# Integration tests
ruby test/test_framework_integration.rb
```

---

## Creating Custom Plugins

To create a custom plugin:

1. Create module file in `lib/plugins/my_plugin.rb`:

```ruby
module MASTER
  module Plugins
    class MyPlugin
      def initialize
        @config = load_config
      end
      
      def validate(target)
        # Plugin logic here
      end
      
      private
      
      def load_config
        YAML.load_file("#{MASTER::ROOT}/lib/config/plugins/my_plugin.yml")
      end
    end
  end
end
```

2. Create configuration in `lib/config/plugins/my_plugin.yml`:

```yaml
settings:
  enabled: true
  rules:
    - rule1: "description"
```

3. Add autoload to `lib/master.rb`:

```ruby
module Plugins
  autoload :MyPlugin, "#{LIB}/plugins/my_plugin"
end
```

4. Create tests in `test/plugins/test_my_plugin.rb`

---

## Best Practices

### 1. Configuration Over Code
Store settings in YAML, not hardcoded in modules.

### 2. Fail Fast
Validate configuration on module initialization.

### 3. Clear Error Messages
Provide actionable feedback on violations.

### 4. Performance
Cache expensive operations, use mtime for config reloading.

### 5. Testing
Test each module independently and integration scenarios.

---

## Migration from pub/pub2/pub3

If migrating from previous versions:

1. **Framework**: Already integrated, verify config paths
2. **Plugins**: Already integrated, verify config paths
3. **Session Recovery**: Moved to `lib/core/session_recovery.rb`
4. **Git Hooks**: Use `bin/install-hooks` to enable
5. **Documentation**: Now in `docs/` directory

---

## Troubleshooting

### Module Not Loading

Check autoload paths in `lib/master.rb`:
```bash
ruby -e "require './lib/master'; puts MASTER::Framework::BehavioralRules"
```

### Configuration Not Found

Verify config file exists:
```bash
ls -la lib/config/framework/*.yml
ls -la lib/config/plugins/*.yml
```

### Gate Failures

Check gate status:
```bash
bin/cli gates status
bin/cli gates check --verbose
```

---

## Further Reading

- [PRINCIPLES.md](PRINCIPLES.md) - Core principles enforced by framework
- [ENFORCEMENT.md](ENFORCEMENT.md) - Git hooks and validation
- [SESSION_RECOVERY.md](SESSION_RECOVERY.md) - Checkpoint system
- [README.md](README.md) - Main documentation index

---

**Version**: MASTER v52.0 REFLEXION  
**Last Updated**: 2024-02-05  
**Framework Modules**: 5  
**Plugin Modules**: 4
