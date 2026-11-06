# frozen_string_literal: true

# The constants and readers layout_contract_test.rb shares with the tests split
# out of it to keep each file under its length ceiling.
module LayoutContractSources
  include StylesheetModules

  # __dir__ is RAILS/test → ROOT is RAILS/ → REPO is pub4 checkout root.
  ROOT = File.expand_path("../..", __dir__)
  REPO = File.expand_path("..", ROOT)
  SHARED = File.join(ROOT, "__shared")
  FACE_CSS = File.join(ROOT, "..", "MASTER", "web", "public", "face.css")
  TOKENS = File.join(SHARED, "design_tokens.yml")
  LAYOUT_CHROME = File.join(SHARED, "app", "assets", "stylesheets", "_layout_chrome.scss")
  SHELL_WIDGETS = File.join(SHARED, "app", "assets", "stylesheets", "_shell_widgets.scss")
  SHELL = File.join(SHARED, "app", "assets", "stylesheets", "_shell.scss")
  DIALECT = File.join(SHARED, "app", "assets", "stylesheets", "_dialect_tokens.scss")
  # One stylesheet per app: the former vertical partials are modules of
  # brgen/application.scss.

  LAYOUTS = {
    "brgen" => File.join(ROOT, "brgen", "app", "views", "layouts", "application.html.erb"),
    "amber" => File.join(ROOT, "amber", "app", "views", "layouts", "application.html.erb"),
    "bsdports" => File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb"),
    "master_chat" => File.join(ROOT, "..", "MASTER", "web", "app", "views", "chat", "index.html.erb"),
    "master_dashboard" => File.join(ROOT, "..", "MASTER", "web", "app", "views", "dashboard", "index.html.erb"),
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
  # here is `tag.h1`, so the check has been reading a fraction of the headings and
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

  def app_rules(app, selector)
    Operator::ScssRules.matching(stylesheet_source(app), selector)
  end

  # The nav-height token already includes env(safe-area-inset-top); shell,
  # map and radio offsets must not add the same inset a second time.
  def assert_shell_counts_safe_area_once(shell)
    chrome = File.read(LAYOUT_CHROME)
    assert_match(/--nav-swiper-h:\s*calc\([^;]*var\(--safe-top\)\);/m, chrome)
    assert_includes shell, "inset: calc(var(--top-band-block) + var(--nav-swiper-h)) 0 0 0;"
    refute_match(/inset:\s*calc\(var\(--top-band-block\)\s*\+\s*var\(--nav-swiper-h\)\s*\+\s*var\(--safe-top\)\)/, shell)
  end
end
