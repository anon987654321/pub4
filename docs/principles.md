# Principles

Comprehensive explanations of principles referenced in `master.json`.

## Critical Tier (Veto Power - Violations Block Merge)

### preserve_functionality
**Rule**: Working code beats pretty code - never break existing functionality

**Rationale**:
- Formatting is reversible, broken is not
- Preserve then improve, never break
- CSS-only changes when possible

**Detect**: functionality_loss, code_deletion, destructive_rewrite

**Solutions**: css_only_changes, never_touch_working_js, gradual_refinement

### semantic_html_css
**Rule**: Semantic HTML, minimal classes, element selectors first

**Selector Hierarchy**:
1. Element selectors: `h1, p, table, a`
2. Attribute selectors: `[type='email'], [aria-label]`
3. Combinators: `header h1, footer a`
4. Pseudo-classes: `:hover, :focus, :first-child`
5. Classes: `.component` (reusable components only)
6. IDs: `#never` (JavaScript hooks only)

**Forbidden**: class soup, utility classes everywhere, styling with IDs, non-semantic classes, inline styles

**Exceptions**: `.is-active`, `.is-hidden` (JavaScript state), framework-required classes

### no_null
**Rule**: Never return/accept null - use NullObject or Result pattern

**Why**: Null checks scatter throughout codebase. NullObject pattern centralizes handling.

**Pattern**:
```ruby
class NullUser
  def name; "Guest"; end
  def admin?; false; end
end

# Instead of: user.nil? ? "Guest" : user.name
# Use: user.name  # NullUser returns "Guest"
```

### security
**Rule**: No SQLi/XSS/CSRF/injection - sanitize all inputs

**Required**:
- Parameterized queries (no string concatenation)
- HTML escaping in views
- CSRF tokens on forms
- Content Security Policy headers
- Input validation on all user data

## High Tier (Core Quality - Violations Require Justification)

### DRY (Don't Repeat Yourself)
**Rule**: Single source of truth - duplication >70% must be extracted

**Threshold**: If code similarity exceeds 70%, extract to method/module/constant

**Example**:
```ruby
# BAD - duplication
def format_user_name(user)
  "#{user.first_name} #{user.last_name}".strip.titleize
end

def format_author_name(author)
  "#{author.first_name} #{author.last_name}".strip.titleize
end

# GOOD - extracted
def format_full_name(person)
  "#{person.first_name} #{person.last_name}".strip.titleize
end
```

### KISS (Keep It Simple, Stupid)
**Rule**: Simplest solution - prefer boring over clever

**Indicators**:
- Can you explain it in one sentence?
- Would a junior developer understand it?
- Are there fewer than 3 concepts involved?

**Prefer**: Explicit loops over metaprogramming, simple conditions over complex boolean algebra

### YAGNI (You Aren't Gonna Need It)
**Rule**: Delete unused code immediately - no speculation

**Delete Immediately**:
- Commented-out code (git has history)
- Unused methods/classes
- Speculative abstractions
- "Just in case" features

### SOLID
**Principles**:
- **S**ingle Responsibility: One reason to change
- **O**pen/Closed: Open for extension, closed for modification
- **L**iskov Substitution: Subtypes must be substitutable for base types
- **I**nterface Segregation: Many specific interfaces > one general interface
- **D**ependency Inversion: Depend on abstractions, not concretions

## Medium Tier (Polish - Violations Are Warnings)

### Strunk & White
**Rules**:
1. Omit needless words
2. Use vigorous English
3. Be definite, specific, concrete
4. Avoid fancy words
5. Do not explain too much

### Rails Doctrine
**9 Principles**:
1. Optimize for programmer happiness
2. Convention over configuration
3. The menu is omakase (curated stack)
4. No one paradigm (mix OOP/functional as needed)
5. Beautiful code matters
6. Provide sharp knives (power tools for experts)
7. Value integrated systems
8. Progress over stability
9. Push up the big tent (inclusive community)

### Unix Philosophy
**Rules**:
1. Do one thing and do it well
2. Write programs to work together
3. Write programs to handle text streams (universal interface)
4. Avoid captive user interfaces
5. Make every program a filter
6. Expect output to become input to another program
7. Design for simplicity - add complexity only where necessary
8. Build prototypes as soon as possible
9. Choose portability over efficiency
10. Store data in flat text files
11. Use software leverage to your advantage
12. Use shell scripts to increase leverage and portability

## Meta Tier

### fixed_point_convergence
**Pattern**: Silence is convergence proof

**Process**:
1. Run full scan for violations
2. Fix all detected violations
3. Re-run scan
4. If zero violations found: **CONVERGED**
5. If violations found: Repeat from step 2

**Proof**: Two consecutive scans with zero violations = fixed-point reached

## External References

- **Martin Fowler**: Refactoring, Patterns of Enterprise Application Architecture
- **Robert C. Martin**: Clean Code, Clean Architecture, SOLID principles
- **Gang of Four**: Design Patterns
- **Kent Beck**: Test-Driven Development
- **DHH**: Rails Doctrine, Getting Real
- **Strunk & White**: The Elements of Style
- **Bringhurst**: The Elements of Typographic Style
