# Framework Integration Guide

MASTER includes a comprehensive framework system with behavioral rules, universal standards, workflow automation, quality gates, and Copilot optimization. This guide explains how to use and configure these modules.

## Table of Contents

- [Overview](#overview)
- [Framework Modules](#framework-modules)
  - [Behavioral Rules](#behavioral-rules)
  - [Universal Standards](#universal-standards)
  - [Workflow Engine](#workflow-engine)
  - [Quality Gates](#quality-gates)
  - [Copilot Optimization](#copilot-optimization)
- [Plugin System](#plugin-system)
  - [Design System Plugin](#design-system-plugin)
  - [Web Development Plugin](#web-development-plugin)
  - [Business Strategy Plugin](#business-strategy-plugin)
  - [AI Enhancement Plugin](#ai-enhancement-plugin)
- [Configuration](#configuration)
- [Integration Examples](#integration-examples)

## Overview

The framework system provides:
- **Behavioral enforcement**: Rules for code behavior and patterns
- **Universal standards**: Cross-project conventions
- **Workflow automation**: Seven-phase development process
- **Quality gates**: Automated quality checks at phase boundaries
- **Copilot optimization**: Enhanced AI assistance configuration

Plugins extend the framework with domain-specific capabilities:
- **Design System**: Visual design patterns and components
- **Web Development**: Frontend and backend best practices
- **Business Strategy**: Project planning and analysis
- **AI Enhancement**: Advanced LLM integrations

## Framework Modules

### Behavioral Rules

**Location**: `lib/framework/behavioral_rules.rb`  
**Config**: `lib/config/framework/behavioral_rules.yml`

Enforces coding behavior patterns beyond syntax.

#### Features

- **Pattern Detection**: Regex and semantic checking
- **Context-Aware**: Considers surrounding code
- **Configurable Severity**: Critical, high, medium, low
- **Category Organization**: Security, performance, maintainability

#### Usage

```ruby
require_relative 'lib/master'

# Load rules
rules = MASTER::Framework::BehavioralRules.rules

# Validate code
code = File.read('example.rb')
result = MASTER::Framework::BehavioralRules.validate_behavior(code)

if result[:valid]
  puts "✓ No behavioral violations"
else
  result[:violations].each do |violation|
    puts "#{violation[:severity]}: #{violation[:message]}"
    puts "  Line #{violation[:line]}: #{violation[:pattern]}"
  end
end
```

#### Configuration

Edit `lib/config/framework/behavioral_rules.yml`:

```yaml
rules:
  - category: security
    name: sql_injection
    description: "Detect potential SQL injection"
    enabled: true
    severity: critical
    patterns:
      - type: regex
        pattern: 'User\.where\(".*#{.*}.*"\)'
        message: "Use parameterized queries"
        
  - category: performance
    name: n_plus_one
    description: "Detect N+1 query patterns"
    enabled: true
    severity: high
    patterns:
      - type: semantic
        indicator: "loop with database query"
        message: "Use eager loading"
```

### Universal Standards

**Location**: `lib/framework/universal_standards.rb`  
**Config**: `lib/config/framework/universal_standards.yml`

Defines conventions that apply across all projects.

#### Standards Included

- **Naming Conventions**: Files, classes, methods, variables
- **Code Organization**: Directory structure, module layout
- **Documentation**: Comment styles, README requirements
- **Testing**: Test structure, coverage expectations
- **Version Control**: Commit messages, branch naming

#### Usage

```ruby
standards = MASTER::Framework::UniversalStandards.config

# Check naming
standards[:naming][:class_name_pattern]  # => /^[A-Z][a-zA-Z0-9]*$/
standards[:naming][:method_name_pattern] # => /^[a-z_][a-z0-9_]*$/

# Validate file structure
result = MASTER::Framework::UniversalStandards.validate_structure('lib/')
```

#### Configuration

```yaml
naming:
  class_name_pattern: "^[A-Z][a-zA-Z0-9]*$"
  method_name_pattern: "^[a-z_][a-z0-9_]*$"
  constant_pattern: "^[A-Z_][A-Z0-9_]*$"
  
structure:
  required_directories:
    - lib
    - test
    - docs
    - bin
  required_files:
    - README.md
    - Gemfile
    
documentation:
  min_class_comment_lines: 3
  require_method_comments: true
  readme_sections:
    - Overview
    - Installation
    - Usage
    - Examples
```

### Workflow Engine

**Location**: `lib/framework/workflow_engine.rb`  
**Config**: `lib/config/framework/workflow_engine.yml`

Automates the seven-phase development process.

#### Seven Phases

1. **Discover**: Understand requirements
2. **Analyze**: Break down the problem
3. **Ideate**: Generate solutions
4. **Design**: Plan architecture
5. **Implement**: Write code
6. **Validate**: Test and verify
7. **Deliver**: Deploy and document

#### Usage

```ruby
# Initialize workflow
workflow = MASTER::Framework::WorkflowEngine.new

# Start phase
workflow.start_phase(:discover)

# Execute phase tasks
workflow.execute_task('gather_requirements')
workflow.execute_task('identify_stakeholders')

# Complete phase
workflow.complete_phase(:discover)

# Move to next
workflow.start_phase(:analyze)

# Check current state
puts workflow.current_phase  # => :analyze
puts workflow.completed_phases  # => [:discover]
```

#### Phase Configuration

```yaml
phases:
  discover:
    name: "Discover"
    description: "Understand the problem domain"
    tasks:
      - gather_requirements
      - identify_stakeholders
      - define_scope
    gates:
      - requirements_documented
      - stakeholders_identified
      
  analyze:
    name: "Analyze"
    description: "Break down the problem"
    tasks:
      - decompose_requirements
      - identify_constraints
      - assess_risks
    gates:
      - problem_decomposed
      - risks_documented
```

### Quality Gates

**Location**: `lib/framework/quality_gates.rb`  
**Config**: `lib/config/framework/quality_gates.yml`

Enforces quality standards at phase boundaries.

#### Gate Types

- **Code Quality**: Complexity, duplication, style
- **Test Coverage**: Minimum coverage thresholds
- **Documentation**: Required docs, completeness
- **Security**: Vulnerability scans, dependency checks
- **Performance**: Benchmarks, regression tests

#### Usage

```ruby
# Check if ready to proceed
gates = MASTER::Framework::QualityGates

# Run all gates for phase
result = gates.check_phase_gates(:implement)

if result[:passed]
  puts "✓ All gates passed, ready to move to validate phase"
else
  puts "✗ Gates failed:"
  result[:failures].each do |failure|
    puts "  - #{failure[:gate]}: #{failure[:reason]}"
  end
end
```

#### Gate Configuration

```yaml
gates:
  implement:
    - name: code_quality
      type: complexity
      threshold: 10
      required: true
      
    - name: test_coverage
      type: coverage
      threshold: 80
      required: true
      
    - name: documentation
      type: docs
      check: all_public_methods_documented
      required: false
      
  validate:
    - name: integration_tests
      type: test_suite
      suite: integration
      required: true
      
    - name: performance_benchmark
      type: performance
      max_regression: 0.05
      required: true
```

### Copilot Optimization

**Location**: `lib/framework/copilot_optimization.rb`  
**Config**: `lib/config/framework/copilot_optimization.yml`

Optimizes AI assistance for development workflows.

#### Features

- **Context Management**: Smart context inclusion
- **Prompt Optimization**: Better AI responses
- **Cost Control**: Token budgets, model selection
- **Quality Feedback**: Learn from interactions

#### Usage

```ruby
optimizer = MASTER::Framework::CopilotOptimization

# Optimize prompt
prompt = "Write a function to process user data"
optimized = optimizer.optimize_prompt(prompt, context: {
  language: 'ruby',
  style: 'functional',
  constraints: ['pure functions', 'no globals']
})

# Get model recommendation
model = optimizer.recommend_model(
  task_type: :code_generation,
  complexity: :high,
  budget: :medium
)

# => { model: 'claude-sonnet', reasoning: '...' }
```

#### Configuration

```yaml
context:
  max_tokens: 8000
  include_principles: true
  include_recent_files: 5
  
models:
  code_generation:
    simple: grok-beta
    medium: claude-sonnet
    complex: claude-sonnet
    
  analysis:
    simple: deepseek-chat
    medium: claude-sonnet
    complex: o1-preview
    
cost_limits:
  per_request: 0.50
  per_session: 10.00
  daily: 100.00
```

## Plugin System

Plugins extend framework capabilities with specialized functionality.

### Design System Plugin

**Location**: `lib/plugins/design_system.rb`  
**Config**: `lib/config/plugins/design_system.yml`

Manages visual design patterns and component libraries.

#### Features

- **Color Systems**: Palettes, contrast validation
- **Typography**: Scale, hierarchy, rhythm
- **Spacing**: Consistent spacing units
- **Components**: Reusable UI components
- **Accessibility**: WCAG compliance checking

#### Usage

```ruby
# Enable plugin
MASTER::Plugins::DesignSystem.enable

# Configure
MASTER::Plugins::DesignSystem.configure(
  colors: {
    primary: '#007bff',
    secondary: '#6c757d',
    success: '#28a745',
    danger: '#dc3545'
  },
  typography: {
    base_size: 16,
    scale_ratio: 1.25
  }
)

# Apply to context
result = MASTER::Plugins::DesignSystem.apply(
  component: 'button',
  variant: 'primary',
  size: 'medium'
)

# Generate component
button = result[:styles]
# => { padding: '8px 16px', background: '#007bff', ... }
```

#### Configuration

```yaml
enabled: true

colors:
  primary: '#007bff'
  secondary: '#6c757d'
  
typography:
  base_size: 16
  scale_ratio: 1.25
  fonts:
    sans: 'Inter, system-ui, sans-serif'
    mono: 'SF Mono, Consolas, monospace'
    
spacing:
  unit: 8
  scale: [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 16]
  
accessibility:
  wcag_level: 'AA'
  contrast_ratio: 4.5
```

### Web Development Plugin

**Location**: `lib/plugins/web_development.rb`  
**Config**: `lib/config/plugins/web_development.yml`

Best practices for web application development.

#### Features

- **Frontend Patterns**: React, Vue, vanilla JS
- **Backend Patterns**: Rails, Sinatra, REST APIs
- **Security**: XSS, CSRF, SQL injection prevention
- **Performance**: Caching, CDN, optimization
- **SEO**: Meta tags, structured data

#### Usage

```ruby
MASTER::Plugins::WebDevelopment.enable

# Validate route structure
result = MASTER::Plugins::WebDevelopment.validate_routes('config/routes.rb')

# Check security headers
headers = MASTER::Plugins::WebDevelopment.required_security_headers
# => ['X-Frame-Options', 'X-Content-Type-Options', ...]

# Generate API endpoint
endpoint = MASTER::Plugins::WebDevelopment.generate_endpoint(
  resource: 'users',
  actions: [:index, :show, :create, :update, :destroy]
)
```

### Business Strategy Plugin

**Location**: `lib/plugins/business_strategy.rb`  
**Config**: `lib/config/plugins/business_strategy.yml`

Business analysis and strategic planning tools.

#### Features

- **Market Analysis**: Competitor research, positioning
- **Financial Modeling**: Revenue projections, costs
- **Risk Assessment**: SWOT, risk matrices
- **Roadmapping**: Feature prioritization, timelines
- **Metrics**: KPIs, success criteria

#### Usage

```ruby
MASTER::Plugins::BusinessStrategy.enable

# Analyze market
analysis = MASTER::Plugins::BusinessStrategy.analyze_market(
  industry: 'saas',
  target_segment: 'developers'
)

# Create roadmap
roadmap = MASTER::Plugins::BusinessStrategy.create_roadmap(
  vision: '...',
  timeframe: '12 months',
  resources: { developers: 3, budget: 100000 }
)
```

### AI Enhancement Plugin

**Location**: `lib/plugins/ai_enhancement.rb`  
**Config**: `lib/config/plugins/ai_enhancement.yml`

Advanced LLM integration features.

#### Features

- **Multi-Model Orchestration**: Combine models strategically
- **Prompt Engineering**: Advanced prompting techniques
- **Context Optimization**: Smart context window usage
- **Quality Scoring**: Evaluate AI responses
- **Fine-Tuning**: Model adaptation

#### Usage

```ruby
MASTER::Plugins::AIEnhancement.enable

# Use multi-model synthesis
result = MASTER::Plugins::AIEnhancement.synthesize(
  prompt: "Explain quantum computing",
  models: ['claude-sonnet', 'gpt-4', 'gemini-pro'],
  strategy: :consensus
)

# Optimize context
context = MASTER::Plugins::AIEnhancement.optimize_context(
  files: ['file1.rb', 'file2.rb'],
  max_tokens: 8000,
  priority: :relevance
)
```

## Configuration

### Loading Configuration

All modules and plugins use YAML configuration:

```ruby
# Framework modules
config = YAML.load_file('lib/config/framework/behavioral_rules.yml', symbolize_names: true)

# Plugins
config = YAML.load_file('lib/config/plugins/design_system.yml', symbolize_names: true)
```

### Configuration Caching

Configurations are cached and reloaded only when files change:

```ruby
class BehavioralRules
  @config = nil
  @config_mtime = nil
  
  def self.config
    path = config_path
    current_mtime = File.mtime(path)
    
    if @config && @config_mtime == current_mtime
      return @config  # Return cached
    end
    
    @config = YAML.load_file(path)
    @config_mtime = current_mtime
    @config
  end
end
```

### Environment Variables

Override configuration via environment:

```bash
export MASTER_QUALITY_GATES_STRICT=true
export MASTER_COPILOT_BUDGET=5.00
export MASTER_DESIGN_SYSTEM_THEME=dark
```

## Integration Examples

### Example 1: Full Workflow with Gates

```ruby
require_relative 'lib/master'

# Initialize workflow
workflow = MASTER::Framework::WorkflowEngine.new

# Phase 1: Discover
workflow.start_phase(:discover)
# ... do discovery work ...
workflow.complete_phase(:discover)

# Check gates before proceeding
gates = MASTER::Framework::QualityGates
result = gates.check_phase_gates(:discover)

unless result[:passed]
  puts "Cannot proceed: gates failed"
  result[:failures].each { |f| puts "  - #{f[:reason]}" }
  exit 1
end

# Phase 2: Implement
workflow.start_phase(:implement)
# ... write code ...

# Validate behavior during implementation
code = File.read('lib/feature.rb')
behavior_result = MASTER::Framework::BehavioralRules.validate_behavior(code)

if behavior_result[:violations].any?
  puts "Behavioral violations detected!"
  behavior_result[:violations].each { |v| puts "  #{v[:message]}" }
end

workflow.complete_phase(:implement)

# Final quality check
result = gates.check_phase_gates(:implement)
puts result[:passed] ? "✓ Ready for deployment" : "✗ Failed gates"
```

### Example 2: Design System Integration

```ruby
# Enable design system
MASTER::Plugins::DesignSystem.enable

# Load theme
MASTER::Plugins::DesignSystem.configure(
  colors: {
    primary: '#4F46E5',
    secondary: '#10B981'
  },
  spacing: { unit: 8 }
)

# Generate component styles
button_styles = MASTER::Plugins::DesignSystem.apply(
  component: 'button',
  variant: 'primary'
)

card_styles = MASTER::Plugins::DesignSystem.apply(
  component: 'card',
  spacing: 4
)

# Validate accessibility
contrast_ok = MASTER::Plugins::DesignSystem.check_contrast(
  foreground: '#FFFFFF',
  background: '#4F46E5'
)
```

### Example 3: AI-Enhanced Development

```ruby
# Enable AI enhancement
MASTER::Plugins::AIEnhancement.enable

# Optimize for current task
optimizer = MASTER::Framework::CopilotOptimization

# Get context for AI
context = optimizer.get_context(
  task: :refactoring,
  files: Dir['lib/**/*.rb']
)

# Get model recommendation
model = optimizer.recommend_model(
  task_type: :refactoring,
  complexity: :high
)

# Use AI with optimized prompt
prompt = optimizer.optimize_prompt(
  "Refactor this class to follow SOLID principles",
  context: context
)

# Make request with recommended model
result = MASTER::LLM.generate(prompt, model: model[:model])
```

---

For more details:
- See individual module files in `lib/framework/`
- See plugin files in `lib/plugins/`
- See configuration files in `lib/config/framework/` and `lib/config/plugins/`
