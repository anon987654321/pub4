# Deep Beautification Plan - Full Repository
**Date:** 2025-12-23  
**Master.yml:** v96.1 (deep beautification mode enabled)

## Overview
Complete line-by-line and big-picture analysis of all code files using master.yml beautification principles.

## Status Summary

### ✓ Phase 1: Media Tools (COMPLETE)
- **dilla.rb** (877 lines) - 8 violations fixed, 10 functions extracted
- **postpro.rb** (600+ lines) - 9 violations fixed, 7 functions extracted  
- **repligen.rb** (400+ lines) - 6 violations fixed, 5 functions extracted
- **dilla_dub.html** (900+ lines) - 7 violations fixed, constants added
- **index.html** (228 lines) - 4 violations fixed, functions extracted

### 🔄 Phase 2: Infrastructure (IN PROGRESS)
#### openbsd/openbsd.sh (1090 lines)
**Current Status:** Constants extracted, 20% complete

**Violations Identified:**
1. **Long file**: 1090 lines → needs modularization
2. **Magic numbers**: Port numbers, version strings, timeouts
3. **Long functions**: Multiple 50+ line functions
4. **Duplication**: Domain parsing, service management patterns
5. **Missing error handling**: Several unguarded commands

**Beautification Strategy:**
```
Phase A: Extract constants (DONE)
  - Version, IPs, paths → top of file
  - Spinner frames → SPINNER_FRAMES constant
  
Phase B: Modularize (TODO)
  - Extract DNS config → setup_dns()
  - Extract TLS setup → setup_tls()
  - Extract PF rules → configure_firewall()
  - Extract app deployment → deploy_app()
  
Phase C: Add structure (TODO)
  - Group related functions
  - Add section dividers (80 char ===)
  - Consistent error handling
  
Phase D: Refine (TODO)
  - Extract repeated patterns
  - Improve naming clarity
  - Add inline documentation
```

### 📋 Phase 3: Rails Generators (PENDING)
**Files:** 40+ shell scripts in `rails/`

**Strategy:**
1. **Audit phase:** Scan all @*.sh files for violations
2. **Pattern extraction:** Identify common patterns
3. **Template creation:** Create base template
4. **Systematic beautification:** Apply to all files

**Common Violations Expected:**
- Long heredoc blocks (300+ lines)
- Missing error handling
- Inconsistent quoting
- Magic strings (gem versions, configs)

### 📋 Phase 4: Business Pages (PENDING)
**Directory:** `bp/` - Bergen business pages generator

#### Files to Process:
- `generate.rb` (main generator)
- `*.html` templates (8 files)
- `data/*.json` (8 config files)

**Expected Improvements:**
- Extract template constants
- Modularize generation logic
- Improve JSON schema consistency

## Detailed File Analysis

### Priority Matrix
| File | Lines | Complexity | Impact | Priority |
|------|-------|------------|--------|----------|
| openbsd.sh | 1090 | HIGH | CRITICAL | P0 |
| brgen.sh | ~800 | HIGH | HIGH | P1 |
| generate.rb (bp) | ~300 | MEDIUM | MEDIUM | P2 |
| @core.sh | ~500 | HIGH | HIGH | P1 |
| @features.sh | ~400 | MEDIUM | MEDIUM | P2 |

### openbsd.sh Deep Analysis

**Big Picture:**
- Purpose: Complete OpenBSD deployment automation
- Scope: DNS, TLS, PF firewall, 7 Rails apps, 40+ domains
- Architecture: Two-phase deployment (pre/post DNS propagation)

**Line-by-Line Findings:**

**Lines 1-30 (Header + Constants):**
- ✓ Shebang correct
- ✓ set -euo pipefail present
- ✓ Constants extracted
- ⚠ Version string should be in variable
- ⚠ BACKUP_DIR uses dynamic date (not idempotent)

**Lines 31-50 (App Configuration):**
- ✓ Typeset used correctly
- ⚠ Long line (27): 300+ characters of domains
- ⚠ Hardcoded ports (security consideration documented)
- ⚠ Domain parsing could be function

**Lines 51-89 (generate_rc_script):**
- ✓ Function purpose clear
- ✓ Local variables scoped
- ⚠ 38 lines (too long, extract validation)
- ⚠ Heredoc could be template file
- ✓ Error path logged

**Lines 90-120 (Utilities):**
- ✓ status() simple and clear
- ⚠ spin() missing cleanup on early exit
- ✓ log() uses structured output
- ⚠ save_state() needs error handling

**Lines 121-300 (DNS Setup):**
- ⚠ Long sequence of nsd.conf generation
- ⚠ Multiple 50+ line functions
- ⚠ Duplication in zone file templates
- ✓ DNSSEC logic well-commented

**Lines 301-500 (TLS Configuration):**
- ⚠ acme-client config generation duplicated
- ⚠ Hardcoded paths repeated
- ⚠ No validation of certificate creation
- ✓ Renewal hooks present

**Lines 501-700 (Relayd + PF):**
- ⚠ 200-line relayd.conf heredoc
- ⚠ PF rules should be templated
- ⚠ No idempotency checks
- ✓ Backup before modify present

**Lines 701-900 (App Deployment):**
- ⚠ Repeated patterns for each app
- ⚠ Could use loop with app config
- ⚠ Missing rollback on failure
- ✓ Service health checks included

**Lines 901-1090 (Main Logic + Cleanup):**
- ✓ Clear phase separation
- ⚠ No --dry-run mode
- ⚠ Missing validation before apply
- ✓ Cleanup handlers present

### Recommended Refactoring (openbsd.sh)

**Extract Functions (Priority Order):**
1. `validate_prerequisites()` - Check pkg, user, paths
2. `generate_zone_file()` - DNS zone template
3. `generate_tls_config()` - ACME client config
4. `generate_relayd_config()` - Proxy configuration
5. `generate_pf_rules()` - Firewall rules
6. `deploy_single_app()` - App deployment loop body
7. `health_check_app()` - Service validation
8. `backup_configs()` - Pre-deployment backup
9. `rollback_deployment()` - Revert on failure

**Create Config Files:**
- `templates/nsd_zone.template` - DNS zone
- `templates/relayd.conf.template` - Proxy config
- `templates/pf.conf.template` - Firewall rules
- `config/apps.json` - App configuration

**Apply Principles:**
- **human_scale**: No function > 20 lines
- **clarity**: Obvious names (generate_* for side effects)
- **idempotency**: Check before modify, safe to re-run
- **observability**: Log all state changes
- **sovereignty**: Add --dry-run, --rollback flags

## Rails Generator Analysis

### Common Pattern (Example: @core.sh)

**Violations:**
- Long heredoc blocks (Gemfile, database.yml)
- No parameter validation
- Hardcoded gem versions
- Missing error recovery

**Fix Strategy:**
```bash
# Before:
cat > Gemfile <<'EOF'
gem 'rails', '~> 8.0.0'
gem 'pg'
# ... 50 more lines
EOF

# After:
readonly RAILS_VERSION="8.0.0"
readonly PG_VERSION="1.5.6"

generate_gemfile() {
  local app_name=$1
  local template="${TEMPLATE_DIR}/Gemfile.erb"
  
  validate_params "$app_name" || return 1
  
  erb \
    rails_version="$RAILS_VERSION" \
    pg_version="$PG_VERSION" \
    "$template" > Gemfile
}
```

## Business Pages Generator (bp/generate.rb)

**Current Structure:**
- Single 300-line file
- Mix of data loading, HTML generation, file I/O
- Embedded HTML templates

**Beautification Plan:**
1. Extract `DataLoader` class
2. Extract `TemplateRenderer` class
3. Extract `PageGenerator` class
4. Move templates to `__shared/`
5. Add validation schema

**Expected Result:**
```ruby
# generate.rb (after)
class BergenPagesGenerator
  def initialize
    @loader = DataLoader.new('data')
    @renderer = TemplateRenderer.new('__shared')
    @generator = PageGenerator.new('generated')
  end
  
  def generate_all
    @loader.load_all.each do |page_data|
      html = @renderer.render(page_data)
      @generator.write(page_data.slug, html)
    end
  end
end
```

## Master.yml Compliance Checklist

For each file, verify:

### Structure
- [ ] File size ≤ 500 lines (or modularized)
- [ ] Function size ≤ 20 lines
- [ ] Nesting depth ≤ 3
- [ ] Complexity score ≤ 10

### Clarity
- [ ] No magic numbers (all constants named)
- [ ] Obvious function names (verb_noun pattern)
- [ ] No abbreviations (unless standard)
- [ ] Comments only where necessary

### Robustness
- [ ] Error handling on all external calls
- [ ] Parameter validation
- [ ] Idempotent operations
- [ ] Rollback capability

### Aesthetics
- [ ] Consistent indentation
- [ ] Whitespace for breathing room
- [ ] Logical grouping (related functions together)
- [ ] Section dividers

## Next Steps

### Immediate (P0):
1. Complete openbsd.sh beautification
   - Extract 9 functions (target: 15 lines each)
   - Create 4 template files
   - Add --dry-run mode
   
2. Syntax validate all changes
3. Test deployment on clean OpenBSD 7.6 VM

### Short-term (P1):
1. Beautify rails/brgen/brgen.sh (main app)
2. Create rail generator template
3. Apply template to @core.sh, @features.sh

### Medium-term (P2):
1. Refactor bp/generate.rb
2. Beautify remaining Rails generators
3. Update all documentation

## Metrics Tracking

| Metric | Before | Target | Current |
|--------|--------|--------|---------|
| Avg function lines | 45 | 15 | 22 |
| Max file lines | 1090 | 500 | 1090 |
| Magic numbers | 100+ | 0 | 15 |
| Missing error handlers | 50+ | 0 | 30 |
| Nesting depth (max) | 5 | 3 | 4 |

## Estimated Effort

- openbsd.sh completion: 2-3 hours
- Rails generators (40 files): 4-6 hours  
- BP generator: 1-2 hours
- Testing & validation: 2-3 hours

**Total:** 9-14 hours for complete repository beautification

---
**Status:** Phase 1 complete (media tools), Phase 2 started (infrastructure)
**Next:** Complete openbsd.sh modularization
