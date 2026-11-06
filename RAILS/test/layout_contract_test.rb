# frozen_string_literal: true

# Family layout contract: MASTER face + RAILS apps share chrome vars, skip-link,
# main landmark, and 44px tap floor. Dialects may restyle; structure stays.
require "minitest/autorun"
require_relative "engine_roots"
require_relative "../../MASTER/tools/scss"
require_relative "support/stylesheet_modules"
require_relative "support/layout_contract_sources"

class LayoutContractTest < Minitest::Test
  include LayoutContractSources

  # The instrument, against an answer written here rather than derived from it.
  # Five headings in three notations, one of them commented out — if this stops
  # returning [1, 2, 3, 4] the detector has drifted and every count below it is
  # decoration. tools/instruments.rb makes the same argument for MASTER's
  # counters; this is the same idea at the size that fits in a test.
  def test_the_heading_detector_sees_all_three_notations
    sample = <<~ERB
      <%# <h5>commented out, not a heading</h5> %>
      <h1>literal</h1>
      <%= tag.h2 "helper" %>
      <%= content_tag(:h3, "content_tag") %>
      <h4 class="x">attributes</h4>
    ERB

    assert_equal [1, 2, 3, 4], heading_levels(sample)
  end

  def test_no_view_skips_a_heading_level
    views = Dir.glob(File.join(ROOT, "{amber,brgen,bsdports,__shared}", "app", "views", "**", "*.html.erb")) +
            Dir.glob(File.join(ROOT, EngineRoots::GLOB, "app", "views", "**", "*.html.erb"))

    refute_empty views, "no views found — the glob stopped matching, which is blindness not cleanliness"

    skips = views.flat_map do |path|
      heading_levels(File.read(path)).each_cons(2).filter_map do |from, to|
        "#{path.delete_prefix("#{ROOT}/")}: h#{from} -> h#{to}" if to > from + 1
      end
    end

    assert_empty skips.sort,
                 "these views jump a heading level; promote the heading and size it so nothing moves"
  end

  # &nbsp; used as spacing, not as typography.
  #
  # The distinction is what the entity is touching. `~10&nbsp;km` binds a number
  # to its unit so the pair never breaks across a line -- that is what a
  # non-breaking space is for, and it stays. An &nbsp; alone on its line, or
  # alone inside an element, is standing in for a gap or a reserved line box: it
  # collapses at some widths, wraps at others, and is announced as a space.
  #
  # Four were replaced on 2026-08-10 -- three separating meta pairs on the dating
  # profile, now .profile-meta with a flex gap, and one reserving a line box in
  # the marketplace nav, which the storefront flatten removed outright.
  def test_nbsp_is_typography_not_spacing
    views = Dir.glob(File.join(ROOT, "{amber,brgen,bsdports,__shared}", "app", "views", "**", "*.erb")) +
            Dir.glob(File.join(ROOT, EngineRoots::GLOB, "app", "views", "**", "*.erb"))

    refute_empty views, "no views found — the glob stopped matching, which is blindness not cleanliness"

    hacks = views.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("<%#")

        # Flagged when either side is whitespace or an element boundary, i.e.
        # when it separates nothing from nothing.
        next unless line =~ /(?:\A|[\s>])&nbsp;|&nbsp;(?:[\s<]|\z)/

        "#{path.delete_prefix("#{ROOT}/")}:#{i + 1}  #{line.strip[0, 60]}"
      end
    end

    assert_empty hacks.sort,
                 "these &nbsp; are spacing, not typography — use a flex gap, padding, or a CSS-reserved line box"
  end

  def test_layout_chrome_partial_exists
    assert File.file?(LAYOUT_CHROME), "expected _layout_chrome.scss"
    body = File.read(LAYOUT_CHROME)
    assert_includes body, "--tap-min"
    assert_includes body, "--chrome-inset"
    assert_includes body, ".page-header"
  end

  def test_page_header_has_one_mobile_first_authority
    layout = File.read(LAYOUT_CHROME)
    widgets = File.read(SHELL_WIDGETS)

    assert_includes layout, "flex-direction: column"
    assert_includes layout, "@media (min-width: 640px)"
    assert_includes layout, "flex-direction: row"
    refute_match(/\.page-header\s*\{/, widgets,
                 "_shell_widgets must not redefine the shared page-header")
  end

  # Every Rails dialect gets its reading grammar from the shared stack. A page
  # may have a distinct palette and display mark, but measure, body rhythm,
  # numerals and prose behavior must not fork across the three apps.
  def test_each_rails_dialect_mounts_the_shared_typographic_grammar
    stacks = {
      "amber" => "stack",
      "brgen" => "stack_brgen",
      "bsdports" => "stack",
    }

    stacks.each do |app, stack_name|
      source = stylesheet_source(app)
      # One stylesheet per app (operator, 2026-10-28): the shared stack mounts
      # through an unlayered meta.load-css at the top of the merged sheet.
      assert_includes source, %(@include meta.load-css("#{stack_name}");),
                      "#{app} must load its declared shared stack before dialect overrides"
    end

    %w[stack stack_brgen].each do |stack_name|
      stack = File.read(File.join(SHARED, "app/assets/stylesheets/_#{stack_name}.scss"))
      assert_includes stack, '@forward "typography";', "#{stack_name} dropped the shared reading grammar"
      assert_match(/@forward "tokens"(?:\s+with\s+\([^;]+\))?;/, stack, "#{stack_name} dropped the shared type scale")
    end

    typography = File.read(File.join(SHARED, "app/assets/stylesheets/_typography.scss"))
    required_contracts = [
      "--measure: 66ch;",
      "--measure-narrow: 45ch;",
      "--measure-wide: 75ch;",
      "line-height: var(--leading-normal);",
      'font-feature-settings: "kern", "liga", "clig", "onum", "pnum";',
      "font-kerning: normal;",
      "font-optical-sizing: auto;",
      "font-synthesis: none;",
      "font-variant-numeric: oldstyle-nums proportional-nums;",
      "hanging-punctuation: first allow-end last;",
      "text-wrap: pretty;",
      "hyphenate-limit-chars: 6 3 2;",
      "orphans: 3;",
      "widows: 3;",
    ]

    required_contracts.each do |contract|
      assert_includes typography, contract, "shared typography contract drifted: #{contract}"
    end
  end

  def test_app_surfaces_use_explicit_type_and_rhythm_tokens
    brgen = File.read(File.join(ROOT, "brgen", "app/assets/stylesheets/application.scss"))
    amber = File.read(File.join(ROOT, "amber", "app/assets/stylesheets/application.scss"))
    nearby = File.read(File.join(SHARED, "app/assets/stylesheets/_nearby_chat_widget.scss"))

    refute_includes brgen, "font-size: 1.17em;"
    refute_includes amber, "font-size: 1.17em;"
    refute_includes amber, "line-height:.98;"
    assert_includes nearby, "padding: var(--space-2) var(--space-3);"
    assert_includes nearby, "gap: var(--space-2);"
  end

  # The mark is the brand and nothing else, so it is one length on every host.
  #
  # It used to render the whole hostname on a vertical, and that string varying
  # per host needed a gutter reservation, a narrow-width TLD drop and an
  # overflow bound -- because the mark is fixed and takes pointer events, so a
  # host longer than any measured did not look broken, it quietly ate the first
  # taps on the nav's leading link. Measured at 390px before the bound existed:
  # markedsplass.brgen.no overran by 4px and elementFromPoint at the link's own
  # leading edge returned the mark.
  #
  # None of that machinery can come back on its own, but the hostname can. This
  # asserts the mark stays one span, which is the condition all of it hung on.
  def test_the_brand_mark_is_the_brand_and_not_a_hostname
    partial = File.read(File.join(SHARED, "app/views/shared/_brand_mark.html.erb"))

    refute_includes partial, "brand-sub", "a subdomain span is a hostname in the mark again"
    refute_includes partial, "brand-tld", "a TLD span is a hostname in the mark again"
    assert_includes partial, %(<span class="brand-text">), "the mark is one span"

    body = File.read(LAYOUT_CHROME)
    refute_match(/\.brand-mark\s+\.brand-sub/, body,
                 "the gutter arithmetic went with the hostname -- do not restore one without the other")
  end

  def test_retired_brand_class_rules_stay_removed
    partial = File.read(File.join(SHARED, "app", "views", "shared", "_brand_mark.html.erb"))
    minimal = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_minimal.scss"))
    shell = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_shell.scss"))
    focus = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_focus_ring.scss"))

    assert_includes partial, 'fetch(:class_name, "brand-mark")'
    refute_match(/nav\s+\.brand\b/, minimal)
    refute_match(/^\s*\.brand\s*\{/m, shell)
    refute_match(/^\s*\.brand:(?:hover|focus)/m, shell)
    refute_match(/\.brand:focus-visible/, focus)
    assert_includes shell, ".brand-text {", "the live wordmark text styling stays intact"
  end

  def test_shared_chrome_tokens_declare_layout_floor
    # The generator writes these unquoted; the value is the contract, not the quoting.
    yml = File.read(TOKENS)
    assert_match(/chrome_inset:\s*"?12px"?$/, yml)
    assert_match(/tap_min:\s*"?44px"?$/, yml)
    assert_match(/bar_height:\s*"?44px"?$/, yml)
    assert_match(/measure_body:\s*"?66ch"?$/, yml)
  end

  def test_face_root_shares_chrome_inset_and_tap
    css = File.read(FACE_CSS)
    # Absolute unit on purpose — a rem lands on 13.5px at brgen's 18px root.
    assert_includes css, "--chrome-inset: 12px"
    refute_match(/--chrome-inset:\s*[\d.]+rem/, css, "chrome inset must not scale with the root")
    assert_includes css, "--tap-min: 44px"
    assert_includes css, "--bar-height: 44px"
    assert_includes css, "--z-skip: 2000"
    # Generated insets must use chrome-inset, not a raw 12px literal.
    assert_includes css, "calc(var(--chrome-inset) + var(--safe-top))"
  end

  def test_dialect_exports_family_chrome_vars
    scss = File.read(DIALECT)
    assert_includes scss, "--chrome-inset: 12px"
    refute_match(/--chrome-inset:\s*[\d.]+rem/, scss, "chrome inset must not scale with the root")
    assert_includes scss, "--tap-min: 44px"
    assert_includes scss, "--bar-height: 44px"
  end

  # The measure is `--measure`, in _typography.scss, which both stacks @forward.
  # This line asked the dialect for `--measure-body`, which e2dc94299 retired as
  # a second name for the same 66ch — declared three times and used more often
  # than the real one. design_tokens.yml keeps its `measure_body` key because
  # design_metrics reads that YAML; it is not a CSS name. Asserting the retired
  # spelling in the chrome file is how a stale test invites the twin back.
  def test_the_measure_is_declared_once_under_one_name
    typography = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_typography.scss"))

    assert_includes typography, "--measure: 66ch"
    stylesheets = Dir.glob(File.join(File.dirname(SHARED), "{amber,brgen,bsdports,__shared}/app/assets/stylesheets/**/*.scss"))
    declarers = stylesheets.select { |path| File.read(path).match?(/^\s*--measure(?:-body)?\s*:/) }

    assert_equal [File.join(SHARED, "app", "assets", "stylesheets", "_typography.scss")], declarers
  end

  def test_skip_link_is_hard_hidden_until_focus_in_shell_and_face
    shell = File.read(SHELL)
    face = File.read(FACE_CSS)
    [shell, face].each do |body|
      assert_includes body, "clip-path: inset(50%)"
      assert_match(/\.skip-link:focus/, body)
    end
  end
end
