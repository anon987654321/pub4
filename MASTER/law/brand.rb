# frozen_string_literal: true

# law/brand.rb — the Bergen brand-system laws, one Law.define per law.
#
# Source of every law here is a MEASURED failure or a MEASURED decision from
# building the Sommerseth Eiendom and Alfa Bergen sites (RAILS/__other),
# calibrated against bob.no's production design system. The doctrine lives in
# docs/visual/bergen_brand_systems.md; these laws are the line-level teeth
# /fix walks when it repairs that tree.

Law.define(:SIGNAL_COLOR_NAMING) do
  source "Bergen brand systems — one signal colour per identity (bob.no calibration)"
  detect { |line| line.match?(/--(accent|accent-color|secondary-color|highlight-color)\s*:/) }
  fix "Name the single signal colour --signal; no accent/secondary/highlight twins."
  bad  "--accent: #E07A00;"
  good "--signal: #C97E1E;"
end

Law.define(:PAPER_NOT_PURE_WHITE) do
  source "Bergen brand systems — paper tones, not #FFF (storefront_art matte-paper rule)"
  detect { |line| line.match?(/background(-color)?:\s*(#fff\b|#ffffff\b|white)\s*;/i) }
  fix "Paint page scopes with the paper token, never pure white."
  bad  "background: #FFFFFF;"
  good "background: var(--paper);"
end

Law.define(:PARAMETRIC_MARK_ONLY) do
  source "Bergen-snittet v1 — marks derive from a parametric source, never hand-drawn"
  detect { |line| line.match?(/d="M[\d\s.,A-Za-z-]{80,}"/) }
  fix "Compose marks from the parametric constants (src/lib/marks.ts + scripts/gen-marks.mjs); short paths, named parts."
  bad  '<path d="M4 35.5 L22.5 13.5 L41 35.5 M7 43.5 H41 M34.5 9.5 m-5.5 0 a5.5 ..." />'
  good "d={SOMMERSETH.roof}"
end

Law.define(:WORDMASK_OBSERVES_UNCLIPPED) do
  source "Framer Motion + IntersectionObserver — a fully clipped element never intersects"
  # Measured: whileInView on the masked word span (y: 112% inside its own
  # overflow:hidden mask) reports intersection area 0 forever — the headline
  # stayed invisible. Observe the outer, unclipped wrapper; drive the inner
  # spans with animate.
  detect { |line| line.include?("whileInView") && line.match?(/y:\s*'\d+%'/) }
  fix "useInView on the outer wrapper, animate on the inner word spans."
  bad  "<motion.span className=\"wr-word\" initial={{ y: '112%' }} whileInView={{ y: '0%' }}>"
  good "const inView = useInView(outerRef); <motion.span animate={inView ? { y: '0%' } : { y: '112%' }}>"
end

Law.define(:CURSOR_NONE_REQUIRES_CURSOR) do
  source "Bergen brand systems — hiding the cursor is a promise to replace it"
  detect { |line| line.match?(/cursor:\s*none/) }
  fix "Pair cursor:none with a rendered custom cursor, gated by pointer:fine and prefers-reduced-motion."
  bad  ".page { cursor: none; }"
  good ".page { cursor: none; } /* + <Cursor/> rendered, @media (pointer: fine) and (prefers-reduced-motion: no-preference) */"
end

Law.define(:NORWEGIAN_COPY_BOKMAL) do
  source "Bergen brand systems — user-facing copy in Norwegian bokmål (snl.no orthography)"
  detect { |line| line.match?(/(placeholder|title|description|alt)="[A-Za-z]*(?: the |and |with |your )[A-Za-z ]*"/) }
  fix "Write user-facing strings in Norwegian bokmål; å/ø/æ, snl.no orthography."
  bad  'alt="Red cabin by the fjord at dusk"'
  good 'alt="Rødt trehus ved fjorden i kveldslys"'
end
