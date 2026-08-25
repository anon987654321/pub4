# frozen_string_literal: true

# Family layout contract: MASTER face + RAILS apps share chrome vars, skip-link,
# main landmark, and 44px tap floor. Dialects may restyle; structure stays.
require "minitest/autorun"

class LayoutContractTest < Minitest::Test
  # __dir__ is RAILS/test → ROOT is RAILS/ → REPO is pub4 checkout root.
  ROOT = File.expand_path("..", __dir__)
  REPO = File.expand_path("..", ROOT)
  SHARED = File.join(ROOT, "shared")
  FACE_CSS = File.join(REPO, "MASTER", "web", "public", "face.css")
  TOKENS = File.join(SHARED, "design_tokens.yml")
  LAYOUT_CHROME = File.join(SHARED, "app", "assets", "stylesheets", "_layout_chrome.scss")
  SHELL = File.join(SHARED, "app", "assets", "stylesheets", "_shell.scss")
  DIALECT = File.join(SHARED, "app", "assets", "stylesheets", "_dialect_tokens.scss")

  LAYOUTS = {
    "brgen" => File.join(ROOT, "brgen", "app", "views", "layouts", "application.html.erb"),
    "amber" => File.join(ROOT, "amber", "app", "views", "layouts", "application.html.erb"),
    "bsdports" => File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb"),
    "master_chat" => File.join(REPO, "MASTER", "web", "app", "views", "chat", "index.html.erb"),
    "master_dashboard" => File.join(REPO, "MASTER", "web", "app", "views", "dashboard", "index.html.erb"),
  }.freeze

  # A heading level skipped inside one view breaks the outline screen-reader
  # users navigate by. Six sites had it on 2026-08-10 -- five sidebars and a
  # comments section that all went h1 -> h3 -- and each was promoted with a
  # stylesheet rule holding the rendered size, so the outline changed and the
  # pixels did not (measured over CDP against the bundle at HEAD).
  #
  # This scans every view rather than pinning those six paths: the finding list
  # that named them had five, having missed a second h3 in posts/show.html.erb,
  # and a check that only knows the names it was given cannot catch the next one.
  #
  # Per-file, which is the honest limit -- a view rendered into a layout that
  # already carries an h1 is a skip this cannot see. It catches what it claims.
  # A heading is written three ways in this tree and only one of them is a tag.
  #
  # This scanned /<h([1-6])\b/ — literal markup only — while the dominant form
  # here is `tag.h1`, so the gate has been reading a fraction of the headings and
  # passing on what it could not see. posts/show, communities/index and
  # dating/home all head themselves with tag.h1 and were invisible to it.
  #
  # ERB comments are blanked first: a commented-out example beside a heading is
  # documentation, not markup, and counting it makes the fix for a finding read
  # as the finding.
  HEADING = /<h([1-6])\b|\btag\.h([1-6])\b|content_tag\(?\s*:h([1-6])\b/

  def heading_levels(source)
    source.gsub(/<%#.*?%>/m) { |comment| comment.gsub(/[^\n]/, " ") }
          .scan(HEADING)
          .map { |match| match.compact.first.to_i }
  end

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
    views = Dir.glob(File.join(ROOT, "{amber,brgen,bsdports,shared}", "app", "views", "**", "*.html.erb")) +
            Dir.glob(File.join(ROOT, "brgen", "engines", "*", "app", "views", "**", "*.html.erb"))

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
    views = Dir.glob(File.join(ROOT, "{amber,brgen,bsdports,shared}", "app", "views", "**", "*.erb")) +
            Dir.glob(File.join(ROOT, "brgen", "engines", "*", "app", "views", "**", "*.erb"))

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

  # A mark that carries a host is wider than a bare wordmark, and the mark is
  # fixed and takes pointer events — so when it outgrows the gutter the nav
  # clears for it, it does not look broken, it quietly eats the first taps on
  # the nav's leading link. Measured at 390px: markedsplass.brgen.no overran by
  # 4px and elementFromPoint at the link's own leading edge returned the mark.
  #
  # Widening the gutter alone only holds until a longer host exists, so the mark
  # is bounded BY the gutter. That bound is the actual guarantee; this pins it.
  def test_a_brand_mark_carrying_a_host_cannot_outgrow_its_gutter
    body = File.read(LAYOUT_CHROME)

    assert_match(/body:has\(\.brand-mark \.brand-sub\)/, body,
                 "the wider gutter should be keyed on the mark actually having a subdomain")
    bound = body[/\.brand-mark:has\(\.brand-sub\)\s*\{[^}]*\}/m]
    refute_nil bound, "expected .brand-mark:has(.brand-sub) to bound the mark"
    assert_includes bound, "max-inline-size", "the mark has to be bounded, not merely reserved for"
    assert_includes bound, "var(--brand-mark-inline)",
                     "the bound has to be the gutter itself, so the two cannot drift apart"
    assert_includes bound, "overflow: hidden", "an unbounded overflow still paints over the nav"
  end

  def test_shared_chrome_tokens_declare_layout_floor
    yml = File.read(TOKENS)
    assert_match(/chrome_inset:\s*"12px"/, yml)
    assert_match(/tap_min:\s*"44px"/, yml)
    assert_match(/bar_height:\s*"44px"/, yml)
    assert_match(/measure_body:\s*"66ch"/, yml)
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
    assert_includes scss, "--measure-body: 66ch"
  end

  def test_skip_link_is_hard_hidden_until_focus_in_shell_and_face
    shell = File.read(SHELL)
    face = File.read(FACE_CSS)
    [shell, face].each do |body|
      assert_includes body, "clip-path: inset(50%)"
      assert_match(/\.skip-link:focus/, body)
    end
  end

  def test_rails_layouts_mark_document_surface_and_main
    %w[brgen amber bsdports].each do |app|
      body = File.read(LAYOUTS.fetch(app))
      assert_includes body, 'data-layout="document"', "#{app} missing data-layout"
      assert_includes body, "data-surface=", "#{app} missing data-surface"
      assert_includes body, 'class="skip-link"', "#{app} missing skip-link"
      assert_includes body, 'id="main-content"', "#{app} missing main id"
      assert_includes body, "viewport-fit=cover", "#{app} missing viewport-fit"
    end
  end

  def test_master_chat_is_face_layout
    body = File.read(LAYOUTS.fetch("master_chat"))
    assert_includes body, 'data-layout="face"'
    assert_includes body, 'data-surface="face"'
    assert_includes body, "skip-link"
    assert_includes body, 'href="#zin"'
    assert_includes body, "viewport-fit=cover"
  end

  def test_master_dashboard_is_document_layout
    body = File.read(LAYOUTS.fetch("master_dashboard"))
    assert_includes body, 'data-layout="document"'
    assert_includes body, 'id="main-content"'
    assert_includes body, "skip-link"
    assert_includes body, 'role="main"'
  end

  def test_stack_forwards_layout_chrome
    stack = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_stack.scss"))
    brgen = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_stack_brgen.scss"))
    assert_includes stack, "layout_chrome"
    assert_includes brgen, "layout_chrome"
  end
end
