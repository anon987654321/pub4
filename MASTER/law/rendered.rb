# frozen_string_literal: true

# law/rendered.rb - the design-book Laws only a rendered page can answer, one Law.define per law.
#
# Each reads one snapshot that checks/support/geometry_probe/design_laws.js measured through
# CDP (computed styles, line boxes, chrome states, focus stops, text spacing, motion, bytes),
# at 390, 360 and 320 wide before the desktop. The judgement is Deploy::RenderedDesign's, so
# the fixtures below (snapshots) prove each Law at load, the rendered suite's DesignLawsCheck
# runs the same evaluator on every declared surface, and test/test_rendered_design_laws.rb
# renders a bad and a good HTML page per Law in headless Chrome. No Chrome is INCONCLUSIVE.
require_relative "../checks/support/rendered_design"

module Law
  # The rendered snapshot path and the fixture builders the Laws below share.
  module RenderedFixtures
    PATH = Regexp.union(Deploy::RenderedDesign::SNAPSHOT, /\.s?css\z/)
    EXAMPLE = Deploy::RenderedDesign::EXAMPLE
    SNAP = Deploy::RenderedDesign
    PHONE_AREA = 390 * 844
    BLACK = [0, 0, 0, 1].freeze

    module_function

    def page(*elements, **view) = SNAP.fixture(elements:, **view)
    def el(key, **fields) = SNAP.element(key, **fields)
    def snap(**top) = { "probe" => "design_laws", "viewports" => [] }.merge(top.transform_keys(&:to_s)).to_json
    def at(top) = { "x" => 16, "y" => top, "w" => 358, "h" => 24 }
    def sizes(*pixels)
      pixels.each_with_index.map { |size, row| el("p.s#{row}", font_size: size, rect: at(16 + (row * 40))) }
    end
    def scrolled = { "scroll_height" => 3000, "inner_height" => 844 }
    def chrome(**states) = { "chrome" => states.transform_keys(&:to_s), "page" => scrolled }

    def bar(key, share, on_screen: true, **more)
      row = { "key" => key, "area" => share * PHONE_AREA, "on_screen" => on_screen, "display" => "block" }
      row.merge(more.transform_keys(&:to_s))
    end

    def font(weight, face)
      painted = { "familyName" => "Arial", "postScriptName" => face, "glyphCount" => 5, "isCustomFont" => false }
      { "family" => "Arial", "weight" => weight, "style" => "normal", "caps" => "normal", "synthesis" => "weight style",
        "platform" => [painted] }
    end

    def strobe(step) = { "key" => "canvas.strobe", "samples" => (0..20).map { |i| [i * step, i.even? ? 0.0 : 0.9] } }

    def edge(key, left) = el(key, in_main: true, display: "block", content_x: left)

    def input(border)
      el("input", attrs: { "type" => "text" }, border_width: 1, border_color: border, bg: [17, 17, 17, 1],
                  ground: BLACK)
    end

    def card(width, border) = el("div.card", text: "", border_width: width, border_color: border, ground: BLACK)

    def checker(id) = ->(text, file) { SNAP.findings(id, text, file).map { |hit| finding(**hit) } }

    # The parts every rendered Law shares, declared on its Law.define builder.
    def rendered(law, law_id, **said)
      law.instance_exec(law_id, said) do |id, words|
        source words.fetch(:source)
        tags %i[DESIGN UX]
        measures :rendered_ui
        path PATH
        example_path EXAMPLE
        fix words.fetch(:fix)
        bad words.fetch(:bad)
        good words.fetch(:good)
        check(&RenderedFixtures.checker(id))
      end
    end
  end

  F = RenderedFixtures

  Law.define(:TYPE_SIZE_ECONOMY) do
    F.rendered(self, :TYPE_SIZE_ECONOMY,
               source: "Vignelli, The Vignelli Canon (2010), one or two sizes; Bringhurst 3.1.1; " \
                       "operator 2026-11-06: four sizes, two weights",
               fix: "Set the screen in the four shared_chrome sizes (meta, body, title, display) and two weights.",
               bad: F.page(*F.sizes(11, 12, 13, 15, 16, 18)), good: F.page(*F.sizes(13, 16, 20, 28)))
  end

  Law.define(:SIZE_COMPENSATED_SPACING) do
    F.rendered(self, :SIZE_COMPENSATED_SPACING,
               source: "Bringhurst 2.2.1 and 2.1.6-2.1.7; Butterick, line spacing 120-145%; Refactoring UI",
               fix: "Tighten leading (<= 1.25) and tracking (<= 0) on display type; give prose 1.4-1.6 and " \
                    "small type >= 1.4 and open tracking.",
               bad: F.page(F.el("h1", font_size: 40, line_height: 64)),
               good: F.page(F.el("h1", font_size: 40, line_height: 44, letter_spacing: -0.8)))
  end

  Law.define(:NO_FAUX_TYPE) do
    F.rendered(self, :NO_FAUX_TYPE,
               source: "Bringhurst 2.1.9, don't alter letter shapes without cause; Butterick, no fake small caps",
               fix: "Ask only for the weights and caps the shipped faces carry on every platform (400/700 for " \
                    "Arial) and set font-synthesis: none.",
               bad: F.snap(fonts: [F.font(700, "ArialMT")]), good: F.snap(fonts: [F.font(700, "Arial-BoldMT")]))
text = /(?:\A|[\s,>])(?:h[1-6]|p|a|span|li|label|strong|em)\b|title|label|text/
stretch = /transform\s*:[^;]*scale[XY]\(|font-stretch\s*:\s*(?!normal|100%)/
adapter(:whole_file, languages: %i[css scss], bad: "h1 { transform: scaleX(1.2); }\n",
                     good: "h1 { font-weight: 700; }\n") do |src, _file|
  src.scan(/([^{}]*)\{([^{}]*)\}/).filter_map do |selector, body|
    next unless body.match?(stretch) && selector.match?(text)

        finding(line: src[0, src.index(body)].count("\n") + 1, message: "#{selector.strip} stretches its letters")
      end
    end
  end

  Law.define(:CAPS_RUN_SHORT) do
    F.rendered(self, :CAPS_RUN_SHORT,
               source: "Butterick, all caps for less than one line, tracked 5-12%; Bringhurst 2.1.6",
               fix: "Keep capitals to a short label under one line (NY, SOLGT); set sentences in mixed case.",
               bad: F.page(F.el("p.notice", text_transform: "uppercase",
                                            text: "Leveringen er forsinket i dag fordi bilen venter ved kaien")),
               good: F.page(F.el("span.badge", text_transform: "uppercase", text: "NY")))
  end

  Law.define(:ALIGNMENT_NEAR_MISS) do
    F.rendered(self, :ALIGNMENT_NEAR_MISS,
               source: "Mueller-Brockmann, Grid Systems (1981); Ruder, Typography (1967); Vignelli on grids",
               fix: "Put every text and media block on one edge (one padding token); keep a phone to three left edges.",
               bad: F.page(F.edge("h2.title", 16), F.edge("p.meta", 18)),
               good: F.page(F.edge("h2.title", 16), F.edge("p.meta", 16)))
  end

  Law.define(:CHROME_AREA_BUDGET) do
    F.rendered(self, :CHROME_AREA_BUDGET,
               source: "Wroblewski, Mobile First (2011): content before navigation; Tufte's data-ink at page scale; " \
                       "operator, every pixel earns its place",
               fix: "Keep top-of-page chrome under a sixth of a phone screen and let it yield while the reader reads.",
               bad: F.page(**F.chrome(top: [F.bar("header", 0.07), F.bar("nav.tab-bar", 0.05), F.bar("aside", 0.16)])),
               good: F.page(**F.chrome(top: [F.bar("header", 0.05), F.bar("nav.tab-bar", 0.05)])))
  end

  Law.define(:CHROME_YIELDS_ON_READ) do
    F.rendered(self, :CHROME_YIELDS_ON_READ,
               source: "Operator directive operator_every_pixel_earns_its_place (2026-11-06); WCAG 2.4.11; Krug",
               fix: "Translate chrome out of view on scroll-down (transform, not display none) and bring it back " \
                    "on scroll-up, focus and at the top.",
               bad: F.page(**F.chrome(top: [F.bar("header", 0.05)],
                                      down: [F.bar("header", 0, on_screen: false, display: "none")])),
               good: F.page(**F.chrome(top: [F.bar("header", 0.05)], down: [F.bar("header", 0, on_screen: false)],
                                       up: [F.bar("header", 0.05)])))
  end

  Law.define(:FOCUS_NOT_OBSCURED) do
    F.rendered(self, :FOCUS_NOT_OBSCURED,
               source: "WCAG 2.2 SC 2.4.11 Focus Not Obscured (Minimum), AA, and 2.4.12 (Enhanced), AAA",
               fix: "Give html scroll-padding-block equal to the sticky bars' height so focus never lands under them.",
               bad: F.page(focus: [{ "key" => "a.more", "covers" => [{ "key" => "header", "share" => 1.0 }] }]),
               good: F.page(focus: [{ "key" => "a.more", "covers" => [] }]))
    bars = /header|nav|tab-bar|\bbar\b/
    adapter(:whole_file, languages: %i[css scss], bad: "header { position: sticky; top: 0; }\n",
                         good: "html { scroll-padding-block: 52px; }\nheader { position: sticky; }\n") do |src, file|
      pinned = /position\s*:\s*(?:sticky|fixed)/
      sticky = src.scan(/([^{}]*)\{([^{}]*)\}/).find { |selector, body| selector.match?(bars) && body.match?(pinned) }
      siblings = File.file?(file.to_s) ? Dir[File.join(File.dirname(file), "**/*.{css,scss}")].first(200) : []
      padded = src.include?("scroll-padding") || siblings.any? { |other| File.read(other).include?("scroll-padding") }
      next [] if sticky.nil? || padded

      [finding(line: src[0, src.index(sticky[1])].count("\n") + 1, message: "sticky chrome with no scroll-padding")]
    end
  end

  Law.define(:PRIMARY_ACTION_IN_THUMB_REACH) do
    F.rendered(self, :PRIMARY_ACTION_IN_THUMB_REACH,
               source: "Josh Clark, Designing for Touch: the thumb zone; layout_rules.touch.thumb_zone_primary_actions",
               fix: "Place the primary action low and central on a phone: a bottom bar or the end of the form.",
               bad: F.page(F.el("button.order", primary: true, rect: { "x" => 300, "y" => 20, "w" => 70, "h" => 44 })),
               good: F.page(F.el("button.order", primary: true, rect: F.at(780).merge("h" => 44))))
  end

  Law.define(:CURRENT_LOCATION_MARKED) do
    here = { "path" => "/marked" }
    marked = { "aria-current" => "page" }
    home = F.el("a.home", in_nav: true, path: "/home")
    F.rendered(self, :CURRENT_LOCATION_MARKED,
               source: "Krug, Don't Make Me Think (2014): you-are-here indicators; Nielsen heuristic 1",
               fix: "Mark the current nav link with aria-current and a non-colour cue (weight, rule or shape).",
               bad: F.page(F.el("a.marked", in_nav: true, path: "/marked"), home, page: here),
               good: F.page(F.el("a.marked", in_nav: true, path: "/marked", font_weight: 700, attrs: marked), home,
                            page: here))
  end

  Law.define(:COLOR_NOT_SOLE_SIGNAL) do
    online = { "data-state" => "online" }
    F.rendered(self, :COLOR_NOT_SOLE_SIGNAL,
               source: "WCAG 1.4.1 Use of Color; Albers, Interaction of Color (1963)",
               fix: "Carry each state in words, shape or weight as well as colour; tie an invalid field to text.",
               bad: F.page(F.el("span.dot", pid: 1, attrs: online, color: [0, 160, 0, 1]), F.el("span.dot", pid: 1)),
               good: F.page(F.el("span.dot", pid: 1, attrs: online, text: "Online"),
                            F.el("span.dot", pid: 1, text: "Ute")))
  end

  Law.define(:LINK_DISTINGUISHABLE) do
    text = [51, 51, 51, 1]
    F.rendered(self, :LINK_DISTINGUISHABLE,
               source: "WCAG 1.4.1 (G183, F73); Butterick, underline is for links; Krug, obvious clickability",
               fix: "Underline links in running text (text-decoration-thickness 1px, underline-offset .15em).",
               bad: F.page(F.el("a", in_text: true, parent: "p", color: [59, 108, 196, 1], parent_color: text)),
               good: F.page(F.el("a", in_text: true, parent: "p", decoration: "underline", parent_color: text)))
  end

  Law.define(:NON_TEXT_CONTRAST) do
    F.rendered(self, :NON_TEXT_CONTRAST,
               source: "WCAG 1.4.11 Non-text Contrast, AA 3:1; WCAG 2.2 SC 2.4.13; operator 2026-11-06: 3:1",
               fix: "Give inputs, buttons, acting icons and focus rings 3:1 against their surroundings.",
               bad: F.page(F.input([34, 34, 34, 1])), good: F.page(F.input([118, 118, 118, 1])))
  end

  Law.define(:SMALLEST_EFFECTIVE_DIFFERENCE) do
    F.rendered(self, :SMALLEST_EFFECTIVE_DIFFERENCE,
               source: "Tufte, Visual Explanations (1997): the smallest effective difference; Envisioning Information",
               fix: "Draw structure with a 1px rule quieter than the quietest text, or with space alone.",
               bad: F.page(F.card(2, [239, 239, 239, 1])), good: F.page(F.card(1, [51, 51, 51, 1])))
  end

  Law.define(:MUTED_INK_FROM_GROUND) do
    band = [30, 60, 160, 1]
    F.rendered(self, :MUTED_INK_FROM_GROUND,
               source: "Refactoring UI: no grey text on coloured backgrounds; Albers on colour relativity",
               fix: "On a coloured ground, mute the ink with an opacity token (0.6/0.8) or the ground's own hue.",
               bad: F.page(F.el("p.meta", color: [153, 153, 153, 1], own_ground: band)),
               good: F.page(F.el("p.meta", color: [255, 255, 255, 0.8], own_ground: band)))
  end

  Law.define(:TEXT_SPACING_RESILIENCE) do
    F.rendered(self, :TEXT_SPACING_RESILIENCE,
               source: "WCAG 1.4.12 Text Spacing, AA",
               fix: "Let text boxes grow (min-block-size, padding) instead of fixing height with overflow hidden.",
               bad: F.page(spacing: { "clipped" => ["span.chip"], "sideways" => false }),
               good: F.page(spacing: { "clipped" => [], "sideways" => false }))
  end

  Law.define(:FLASH_THRESHOLD) do
    F.rendered(self, :FLASH_THRESHOLD,
               source: "WCAG 2.3.1 Three Flashes or Below Threshold, A",
               fix: "Modulate brightness within 10% or dissolve slower than 3 Hz; never strobe a large area.",
               bad: F.snap(motion: { "surfaces" => [F.strobe(50)] }),
               good: F.snap(motion: { "surfaces" => [F.strobe(600)] }))
  end

  Law.define(:PAGE_WEIGHT_RATCHET) do
    budget = { "script" => 180_000 }
    F.rendered(self, :PAGE_WEIGHT_RATCHET,
               source: "Rams, good design is environmentally friendly; Wroblewski; tokens.pwa.weight",
               fix: "Bring the route under its row in checks/data/page_weight.yml; lower the row when it drops.",
               bad: F.snap(weight: { "route" => "/", "bytes" => { "script" => 420_000 }, "budget" => budget }),
               good: F.snap(weight: { "route" => "/", "bytes" => { "script" => 150_000 }, "budget" => budget }))
  end

  Law.define(:MAEDA_THE_ONE) do
    buy = F.el("button.buy", primary: true, rect: F.at(40).merge("h" => 44))
    sell = F.el("button.sell", primary: true, rect: F.at(84).merge("h" => 44))
    F.rendered(self, :MAEDA_THE_ONE,
               source: "John Maeda, The Laws of Simplicity (2006), Law 10 The One; ONE_PRIMARY_ACTION " \
                       "holds the view's grain, this the card's and the form's",
               fix: "Give each card and form one primary action; make the rest ghost or link buttons.",
               bad: F.page(F.el("div.card", index: 0), buy.merge("host" => 0), sell.merge("host" => 0)),
               good: F.page(F.el("div.card", index: 0), F.el("div.card", index: 1),
                            buy.merge("host" => 0), sell.merge("host" => 1)))
  end
end
