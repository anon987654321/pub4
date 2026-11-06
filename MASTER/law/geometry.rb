# frozen_string_literal: true

# law/geometry.rb - the type and space Laws the geometry probe already measures, one Law.define
# per law. Each reads the probe's payload (geometry_probe/walk.js, geometry_type_walk.js) saved
# as *.geometry.json, through the SpaceChecks the rendered suite runs (RenderedGeometryCheck
# reports them under these ids), so the page is measured once. TYPEFACE_PER_ROLE also reads
# source: the serif rule Operator::TypographyLint carried now lives here. BPLANS/ is exempt.
require_relative "../checks/support/rendered_design/geometry_laws"

module Law
  # Shared parts of the geometry Laws.
  module GeometryPayload
    G = Deploy::RenderedDesign::GeometryLaws
    SWISS_TREES = %r{RAILS/(?:brgen[^/]*|__shared|amber)/.*\.(?:s?css|erb|html)\z}
    FAMILY = /font-family\s*:\s*([^;}]+)/i
    VENDORED = %w[lightgallery.css].freeze

    module_function

    def declare(law, law_id)
      law.instance_exec(law_id) do |id|
        tags %i[TYPOGRAPHY DESIGN]
        measures :rendered_ui
        example_path G::EXAMPLE
        check(&GeometryPayload.checker(id))
      end
    end

    def checker(id) = ->(text, file) { G.findings(id, text, path: file).map { |hit| finding(**hit) } }

    def box(top, height = 24) = { "x" => 16, "y" => top, "w" => 358, "h" => height }

    def grouped(heading_top)
      heading = G.leaf("h2.section", tag: "h2", frect: box(heading_top, 28))
      G.fixture(elements: [G.leaf("p.intro", frect: box(16, 96)), heading, G.leaf("p.body", frect: box(180, 96))])
    end

    def serif_rows(src, file)
      return [] if VENDORED.include?(File.basename(file.to_s)) || file.to_s.include?("/builds/")

      src.each_line.with_index(1).flat_map do |line, number|
        families(line).grep(G::SERIF).map { |name| { line: number, message: "serif family #{name}; use the sans" } }
      end
    end

    def families(line)
      line.scan(FAMILY).flatten.flat_map { |value| value.split(",") }.map { |item| item.strip.delete("\"'") }
    end
  end

  GP = GeometryPayload

  ::Law.define(:TYPEFACE_PER_ROLE) do
    GP.declare(self, :TYPEFACE_PER_ROLE)
    path Regexp.union(GP::G::SNAPSHOT, GP::SWISS_TREES)
    source "Vignelli, The Vignelli Canon: few typefaces, each with a role; operator 2026-10-11 and 2026-11-06"
    fix "Set UI and text in the one sans stack (var(--font)); monospace for chat, terminal and code. " \
        "BPLANS/ may use serifs."
    bad GP::G.fixture(elements: [GP::G.leaf("h1", font_family: "Georgia, serif")])
    good GP::G.fixture(elements: [GP::G.leaf("h1"), GP::G.leaf("pre.terminal", font_family: "Menlo, monospace")])
    adapter(:whole_file, languages: %i[css scss html], example_path: "/repo/RAILS/brgen/app/assets/stylesheets/_t.scss",
                         bad: "h1 { font-family: \"Iowan Old Style\", Georgia, serif; }\n",
                         good: "body { font-family: var(--font), sans-serif; }\n") do |src, file|
      GP.serif_rows(src, file).map { |hit| finding(**hit) }
    end
  end

  ::Law.define(:TABULAR_NUMERALS) do
    GP.declare(self, :TABULAR_NUMERALS)
    path GP::G::SNAPSHOT
    source "Bringhurst 3.2.1 and Butterick: tabular figures where numbers align; worn_type.catalog.require_tabular_nums"
    fix "Set counts, prices, times and table columns with font-variant-numeric: tabular-nums."
    bad GP::G.fixture(tabular: [{ "sel" => "td.price", "numeric" => "normal" }])
    good GP::G.fixture(tabular: [{ "sel" => "td.price", "numeric" => "tabular-nums" }])
  end

  ::Law.define(:HEADING_WRAP_BALANCE) do
    GP.declare(self, :HEADING_WRAP_BALANCE)
    path GP::G::SNAPSHOT
    source "Bringhurst 2.4.8, no stray last word; CSS Text 4, text-wrap: balance"
    fix "Give h1-h3 text-wrap: balance (or pretty) so a heading never ends on one stray word."
    bad GP::G.fixture(elements: [GP::G.leaf("h1", text_lines: 2, text_wrap: "wrap")])
    good GP::G.fixture(elements: [GP::G.leaf("h1", text_lines: 2, text_wrap: "balance")])
  end

  ::Law.define(:NEGATIVE_SPACE_GROUPING) do
    GP.declare(self, :NEGATIVE_SPACE_GROUPING)
    path GP::G::SNAPSHOT
    source "Gestalt proximity (Lupton, Thinking with Type); Refactoring UI, more space between groups; Hara, White"
    fix "Make the space between groups larger than the space within; close any void taller than a third of the screen."
    bad GP.grouped(120)
    good GP.grouped(144)
  end
end
