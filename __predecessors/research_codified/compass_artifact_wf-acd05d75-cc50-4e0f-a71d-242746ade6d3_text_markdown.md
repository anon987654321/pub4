# Codifying Design Excellence for LLM-Driven Automation

**Typography, layout systems, and code craftsmanship principles distilled into programmatic rules for automated design analysis and generation.** This research synthesizes foundational works from Robert Bringhurst, Ellen Lupton, Edward Tufte, Josef Müller-Brockmann, Robert C. Martin, Martin Fowler, and Sandi Metz into actionable guidelines specifically structured for LLM prompt engineering. The rules presented here can be encoded into JSON configurations, applied to CSS analysis via Ferrum, and used to evaluate or generate design systems programmatically.

---

## Typography fundamentals: the numerical backbone

Typography operates on measurable principles that translate directly into CSS values and programmatic evaluation rules. **Line length remains the most critical readability factor**—Bringhurst's "Elements of Typographic Style" establishes 45-75 characters as the optimal range, with 66 characters representing the ideal. For mobile contexts, this narrows to 35-50 characters.

Line height (leading) follows context-dependent ratios: body text requires **1.4-1.6× the font size** (with 1.5 as the accessibility minimum per WCAG), while headlines can tighten to 1.0-1.2× due to larger optical size. Critically, longer line lengths demand proportionally greater line height—this relationship should be encoded as: `if line_length > 60_chars then line_height = 1.5-1.6`.

The modular type scale provides mathematical consistency across all text sizes. The **Major Third ratio (1.25)** offers balanced hierarchy for most applications, while the **Perfect Fourth (1.333)** creates stronger visual contrast for marketing contexts. A 16px base with Major Third progression yields: 10.24px → 12.8px → 16px → 20px → 25px → 31.25px → 39.06px. This can be implemented via CSS custom properties:

```css
:root {
  --ratio: 1.25;
  --text-base: 1rem;
  --text-lg: calc(var(--text-base) * var(--ratio));
  --text-xl: calc(var(--text-base) * var(--ratio) * var(--ratio));
}
```

Letter spacing follows strict contextual rules: **ALL CAPS text requires +0.05em to +0.15em** positive tracking (the absence of this is a detectable error), headlines can tighten slightly to -0.02em, and lowercase body text should never be letterspaced—Frederic Goudy's aphorism "A man who would letterspace lowercase would steal sheep" remains the governing principle.

---

## Hierarchy through contrast: Carl Dair's seven types

Visual hierarchy emerges from deliberate contrast. Carl Dair identified seven typographic contrast types that map to programmatic evaluation:

**Size contrast** requires minimum 1.2× difference between hierarchy levels—anything less fails to create clear visual distinction. H1 should be 2-3× body text size, H2 at 1.5-2×, H3 at 1.25-1.5×. **Weight contrast** needs at least 200 points difference on the font-weight scale (400 vs 600 minimum for clear distinction; 300 vs 500 is insufficient). **Color contrast** must meet WCAG AA minimums: 4.5:1 for normal text, 3:1 for large text (18px+ or 14px bold+).

The consistency principle limits variety: maximum **2 typeface families**, **3 font weights**, and **8 distinct font sizes** per design system. Exceeding these thresholds indicates potential design drift.

---

## Grid systems and spatial relationships

Josef Müller-Brockmann's grid philosophy—"The grid system is an aid, not a guarantee"—establishes the **12-column grid** as the standard division system (divisible by 2, 3, 4, and 6). All spacing should follow an **8-pixel base unit** (Material Design's foundation), producing the scale: 4, 8, 16, 24, 32, 48, 64px.

The golden ratio (1:1.618) governs proportional divisions: a 960px container divides into **593px main content** and **367px sidebar**. For two-column layouts, this approximately 62%/38% split creates optimal visual weight distribution.

**Reading patterns** determine content placement strategy:
- **F-pattern** (text-heavy pages): Critical information in first two paragraphs; front-load important words in headings
- **Z-pattern** (landing pages): Top-left logo → top-right navigation → diagonal to CTA at bottom-right
- **Gutenberg diagram**: Primary optical area (top-left) and terminal area (bottom-right) receive highest attention; weak fallow area (bottom-left) should contain minimal importance content

White space follows the **internal ≤ external rule**: space within elements (padding) must never exceed space between elements (margin). This Gestalt principle ensures related items appear grouped while distinct sections remain visually separated.

---

## Designer philosophies as design rules

**Massimo Vignelli's Canon** reduces to three testable principles: semantics (design must have meaning—reject arbitrary decoration), syntactics (maintain visual grammar consistency across all elements), and pragmatics (ensure understandability and function). His typeface restriction—"Out of thousands of typefaces, all we need are a few basic ones"—supports the two-family maximum rule.

**Dieter Rams' 10 Principles** translate to evaluation criteria: Is the design innovative yet useful? Does it make the product understandable (self-explanatory)? Is it unobtrusive? Is it honest (no false promises)? Is it thorough down to the last detail? These questions can drive automated design scoring.

**Jan Tschichold's asymmetric principle** states that asymmetry creates "the rhythmic expression of functional design." For automated layout generation, this means avoiding default center-alignment in favor of left-aligned body text with strategic emphasis through positioning rather than decoration.

**Paula Scher's expressive typography** principle—"Typography is painting with words"—supports the rule that typeface selection should match emotional content. Her approach justifies mapping font personality to content mood: serif fonts for traditional/trustworthy contexts, geometric sans-serif for modern/innovative positioning, scripts for elegance, bold display faces for impact.

---

## Type designers and screen-optimized principles

**Adrian Frutiger's legibility-first approach** produced Univers (first systematically designed font family with numerical weight classification) and Frutiger (designed for airport signage legibility at various distances). His principles: high x-height increases screen readability, open apertures aid small-size legibility, and warmth comes from humanist rather than strictly geometric forms.

**Matthew Carter's screen optimization** for Verdana and Georgia established critical rules: **bold versions must be significantly bolder** because stem width jumping from 1 to 2 pixels represents a massive visual difference; larger proportions and generous letter spacing compensate for pixel limitations; character disambiguation (1/l/I, 0/O, B/8 must remain distinct) is essential.

**Erik Spiekermann's Meta** was designed as "the complete antithesis of Helvetica"—optimized for worst-case conditions: small sizes, poor paper, uneven printing. This defensive design principle applies to responsive typography: **design for degraded conditions**, not ideal viewport assumptions.

---

## Responsive typography implementation

**Fluid typography using CSS clamp()** replaces breakpoint-based sizing with smooth scaling. The formula calculates slope and y-intercept from desired min/max sizes at min/max viewports:

```css
/* 16px at 320px viewport → 24px at 1200px viewport */
font-size: clamp(1rem, 0.818rem + 0.91vw, 1.5rem);
```

The accessibility requirement: **always include rem in the preferred value** to ensure browser zoom scaling works correctly. Pure vw-based fluid typography fails WCAG compliance.

**Touch target sizing** follows platform guidelines: WCAG 2.5.5 recommends 44×44 CSS pixels (Level AAA), Apple HIG specifies 44×44 points, Material Design requires 48×48 dp. Mobile input fields must be **minimum 16px font-size** to prevent iOS auto-zoom on focus.

**Thumb zone design** places primary actions in the bottom-center "safe zone" for one-handed mobile use. This means bottom navigation bars, floating action buttons at bottom-center, and avoiding critical interactions in top corners (the "oouch zone").

---

## Psychology-driven typography decisions

Research findings establish quantifiable guidelines: **serif vs sans-serif shows minimal difference in reading speed** on modern high-DPI screens (220+ PPI approaches print legibility). However, sans-serif consistently performs better for visually impaired users and dyslexic readers. **Open counters, high x-height, and wider character spacing** improve accessibility more than font classification.

The **disfluency effect** suggests slightly harder-to-read fonts may improve learning retention, but this remains controversial—the primary goal should be reducing cognitive load through optimal line length, appropriate leading, and sufficient contrast.

Eye-tracking research reveals **bold keywords reduce cognitive load** and improve information integration. ALL CAPS disrupts fluency by increasing fixation counts (slowing reading by approximately 30% due to letter-by-letter rather than word-shape processing). Strategic emphasis through size and weight changes guides attention more effectively than decorative treatments.

---

## Edward Tufte's data visualization principles

**Data-ink ratio** should approach 1.0—the proportion of graphic ink devoted to non-redundant data display. The evaluation: ask of every element "Does removing this lose information?" If no, remove it. This eliminates chartjunk: moiré patterns, gratuitous 3D effects, heavy grids, decorative backgrounds.

**The Lie Factor** (effect shown ÷ effect in data) must equal 1.0. Physical measurements in graphics should be directly proportional to numerical quantities. Dimension count in visualization should not exceed dimensions in data.

**Sparklines**—"datawords"—embed word-sized graphics in text with typographic resolution. They require no frames, tick marks, or non-data elements. **Small multiples** enable comparison through series of similar graphs using identical scales and axes.

---

## Clean Code: naming and function rules

Robert C. Martin's principles begin with **meaningful names**: intention-revealing, pronounceable, searchable, and following domain conventions. Classes use nouns (Customer, AddressParser), methods use verbs (postPayment, deletePage), booleans use predicate form (active?, valid?).

**Function rules** establish testable constraints: ideally under 20 lines, single responsibility, one level of abstraction. Argument count follows: zero (niladic) is ideal, one (monadic) is good, two (dyadic) is acceptable, three (triadic) should be avoided, more than three requires parameter object consolidation.

**Command-Query Separation** states functions should either perform an action OR return information, never both. **No side effects** means functions do exactly what their names indicate. **Flag arguments** (boolean parameters) indicate the function should be split into separate methods.

The **Boy Scout Rule**—"Leave the campground cleaner than you found it"—demands incremental improvement with every code touch.

---

## Refactoring: catalog of transformations

Martin Fowler defines refactoring precisely: "A change made to internal structure without changing observable behavior." The process requires test coverage before starting, small incremental changes, tests after each change, and frequent commits separating refactoring from feature additions.

**The Two Hats** (Kent Beck): consciously wear only one at a time—the Refactoring Hat (behavior-preserving changes only, keep tests green) or the Adding Function Hat (new capabilities, new tests, may temporarily break tests). Never mix these activities.

**Code smells as triggers:**
- **Long Method** (>15-20 lines): Extract Method
- **Long Parameter List** (>3-4 params): Introduce Parameter Object
- **Primitive Obsession**: Replace Primitive with Object
- **Feature Envy** (method more interested in another class's data): Move Method
- **Shotgun Surgery** (single change touches many classes): Move Method, Inline Class
- **Switch Statements** on type: Replace Conditional with Polymorphism

**Extract Method** is the most common refactoring—turn code fragments into methods with names explaining purpose. **Replace Temp with Query** extracts expressions into methods, making that calculation available class-wide.

---

## Ruby-specific patterns from Sandi Metz

**POODR's Single Responsibility test**: describe the class in one sentence—if it requires "and" or "or," multiple responsibilities exist. Ask questions of the class: "Mr. Gear, what is your ratio?" (valid) vs "Mr. Gear, what is your tire size?" (responsibility violation).

**Dependency injection** replaces hardcoded class names. Use keyword arguments for initialization:

```ruby
def create_menu(title:, body:, footer: nil)
  # clear parameter purpose
end
```

**Duck typing recognition**: case statements switching on class, uses of `kind_of?`, `is_a?`, or `responds_to?` indicate missing duck types. Replace with polymorphic interfaces.

**Law of Demeter** permits method chains returning intermediate results (`hash.keys.sort.join`) but prohibits chains invoking distant behavior (`customer.bicycle.wheel.rotate`).

**99 Bottles of OOP** introduces **Shameless Green**: first solutions should prioritize understandability over changeability, tolerating duplication until patterns emerge. The **Flocking Rules** for incremental refactoring: select most alike things, find smallest difference, make simplest change to remove difference, repeat.

**Guard clauses** replace nested conditionals:

```ruby
# Instead of nested if statements
def process(user)
  return unless user.present?
  return unless user.active?
  # do work
end
```

---

## Automated CSS analysis rules for Ferrum

For website analysis via Ferrum capturing screenshots and extracting CSS, implement these detection rules:

**Typography violations to flag:**
- Line length outside 45-75 character range (measure via element width / average character width)
- Line height below 1.4 for body text
- Missing letter-spacing on ALL CAPS text (should be 0.05-0.15em)
- Font size below 16px for body text
- Contrast ratio below 4.5:1
- More than 2 font families detected
- More than 3 font weights in use

**Layout violations:**
- Spacing values not on 4px or 8px grid
- Touch targets below 44×44px
- Center-aligned text blocks exceeding 3 lines
- Justified text without hyphenation enabled

**Visual hierarchy checks:**
- Size ratio between heading levels below 1.2×
- Weight difference between hierarchy levels below 200
- Missing visual distinction between content sections

---

## JSON-encodable rule structures

```json
{
  "typography": {
    "lineLength": { "min": 45, "max": 75, "ideal": 66, "unit": "ch" },
    "lineHeight": { "body": { "min": 1.4, "max": 1.6 }, "heading": { "min": 1.0, "max": 1.2 } },
    "fontSize": { "bodyMin": 16, "recommended": 18, "unit": "px" },
    "letterSpacing": { "allCaps": { "min": 0.05, "max": 0.15, "unit": "em" } },
    "contrast": { "normalText": 4.5, "largeText": 3.0 },
    "families": { "max": 2 },
    "weights": { "max": 3 },
    "scales": { "minorThird": 1.2, "majorThird": 1.25, "perfectFourth": 1.333, "golden": 1.618 }
  },
  "spacing": {
    "baseUnit": 8,
    "scale": [4, 8, 16, 24, 32, 48, 64],
    "touchTarget": { "min": 44, "recommended": 48, "unit": "px" }
  },
  "layout": {
    "columns": 12,
    "goldenRatio": 1.618,
    "margins": { "mobile": 16, "tablet": 24, "desktop": 80, "unit": "px" }
  }
}
```

---

## Code quality rules for generation

```json
{
  "naming": {
    "classes": "CamelCase nouns",
    "methods": "snake_case verbs",
    "predicates": "end_with_question_mark?",
    "mutators": "end_with_bang!",
    "constants": "SCREAMING_SNAKE_CASE"
  },
  "functions": {
    "maxLines": 20,
    "maxParameters": 3,
    "singleResponsibility": true,
    "noSideEffects": true,
    "commandQuerySeparation": true
  },
  "smells": {
    "longMethod": { "threshold": 15 },
    "longParameterList": { "threshold": 3 },
    "deepNesting": { "threshold": 3 },
    "duplicateCode": { "similarityThreshold": 0.8 }
  }
}
```

---

## Conclusion: synthesis for automation

The convergence of typography principles (Bringhurst, Müller-Brockmann, Tufte) and code craftsmanship principles (Martin, Fowler, Metz) reveals shared values: **precision through constraint**, **clarity through simplicity**, **consistency through systems**. Both domains reject arbitrary decisions in favor of reasoned, measurable choices.

For LLM prompt engineering, these principles translate to explicit evaluation criteria. Typography rules become CSS property validators. Design philosophy becomes scoring rubrics. Code smells become pattern matchers. The goal is not rigid enforcement but intelligent guidance—knowing rules well enough to recognize when breaking them serves the work.

Müller-Brockmann's dictum applies equally to design systems and code architecture: "The grid system is an aid, not a guarantee. It permits a number of possible uses and each designer can look for a solution appropriate to his personal style. But one must learn how to use the grid; it is an art that requires practice."