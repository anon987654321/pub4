# Workflow-Centric Restructure Plan (Alternative 3)

## Current Structure (6 sections)
```
meta → core → execution → quality → output → reference
```

## Target Structure (5 workflow phases)
```yaml
bootstrap:    # Session initialization
  identity:   # meta.version, purpose, golden_rule, scope
  permissions: # auto_accept, auto_allow_tools
  context:    # execution_context, hooks
  discovery:  # self_discovery, bootstrap_protocol
  
analyze:      # Detection phase
  principles: # core.principles.universal (27 principles with trigger/action/priority/detector)
  constraints: # core.constraints (banned, allowed, thresholds)
  detectors:  # reference.detectors.implementations (19 detectors)
  categories: # core.violation_categories (9 categories)
  
fix:          # Remediation phase
  remediation: # core.remediation_actions (9 action sets)
  patterns:   # core.patterns (14 situation→action mappings)
  refactoring: # core.principles.refactoring (structural_ops, catalog)
  formatters: # execution.formatter_mental_model
  
verify:       # Validation phase
  quality_gates: # quality.quality_gates, veto_rules
  convergence: # execution.universal_execution_protocol.convergence_detection
  adversarial: # quality.adversarial_personas
  verification: # quality.verification
  
reference:    # Implementation details
  tech_stack: # reference.tech_stack, technology
  language_specific: # reference.language_guidance, language_specific_detectors
  constants: # reference.constants
  shell_zsh: # execution.shell_zsh
  ruby_rails: # execution.ruby_rails
  javascript: # execution.javascript
  html_css: # execution.html_css
  openbsd: # execution.openbsd
  git_workflow: # execution.git_workflow
  ai_assisted: # execution.ai_assisted
```

## Migration Steps
1. Create new structure with 5 root sections
2. Move meta → bootstrap.identity
3. Move core.principles → analyze.principles  
4. Move core.constraints → analyze.constraints
5. Move reference.detectors → analyze.detectors
6. Move core.patterns → fix.patterns
7. Move execution.formatter → fix.formatters
8. Move quality sections → verify
9. Move tech_stack details → reference
10. Update version to 38.0.0 (major restructure)
11. Run self-run to verify

## Benefits
- Matches execution flow: init → scan → fix → check → lookup
- Cognitive load: 5 phases (within 7±2 limit)
- Each phase <9 subsections
- Discoverable by workflow stage
- Independent phase updates

## Preserve
- All 27 principles with complete metadata
- All 19 detector implementations
- All 14 patterns
- All tech-specific conventions
