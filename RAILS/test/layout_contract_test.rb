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
    stylesheets = Dir.glob(File.join(File.dirname(SHARED), "{amber,brgen,bsdports,shared}/app/assets/stylesheets/**/*.scss"))
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

  # A bar that hides on a timer needs a way back, and on a mouse the edge zone
  # is the only one: the hidden state is translateY(-100%) with opacity 0, so
  # pointerenter can never fire on the element itself. zone defaults to 0 and
  # the controller registers its pointermove listener only when zone > 0, so
  # leaving it unset is a bar that leaves and stays gone -- silently, because
  # touch and keyboard still recover it and only the mouse is stranded.
  def test_brgen_nav_can_come_back_on_a_mouse
    partial = File.read(File.join(ROOT, "brgen/app/views/shared/_nav_swiper.html.erb"))
    zone = partial[/data-nav-autohide-zone-value="(\d+)"/, 1]

    refute_nil zone, "nav_swiper sets no edge zone, so a mouse cannot recover the bar"
    assert_operator zone.to_i, :>, 0

    controller = File.read(File.join(ROOT, "shared/frontend/nav_autohide_controller.js"))
    assert_includes controller, "if (this.zoneValue > 0)",
                    "the zone guard is what makes an unset zone silent — keep them described together"
  end

  def test_theme_root_uses_dynamic_viewport_height
    brgen = File.read(File.join(ROOT, "brgen/app/assets/stylesheets/_root.scss"))
    amber = File.read(File.join(ROOT, "amber/app/assets/stylesheets/_variables.scss"))
    assert_match(/\.theme-root\s*\{\s*min-height:\s*100dvh/, brgen)
    assert_match(/\.theme-root\s*\{\s*min-height:\s*100dvh/, amber)
  end

  def test_messenger_dock_reads_keyboard_inset
    css = File.read(File.join(ROOT, "brgen/app/assets/stylesheets/_vertical_messenger_thread.scss"))
    assert_includes css, "var(--keyboard-inset"
  end
end
