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

  def test_layout_chrome_partial_exists
    assert File.file?(LAYOUT_CHROME), "expected _layout_chrome.scss"
    body = File.read(LAYOUT_CHROME)
    assert_includes body, "--tap-min"
    assert_includes body, "--chrome-inset"
    assert_includes body, ".page-header"
  end

  def test_shared_chrome_tokens_declare_layout_floor
    yml = File.read(TOKENS)
    assert_match(/chrome_inset:\s*"0\.75rem"/, yml)
    assert_match(/tap_min:\s*"44px"/, yml)
    assert_match(/bar_height:\s*"44px"/, yml)
    assert_match(/measure_body:\s*"66ch"/, yml)
  end

  def test_face_root_shares_chrome_inset_and_tap
    css = File.read(FACE_CSS)
    assert_includes css, "--chrome-inset: 0.75rem"
    assert_includes css, "--tap-min: 44px"
    assert_includes css, "--bar-height: 44px"
    assert_includes css, "--z-skip: 2000"
    # Generated insets must use chrome-inset, not a raw 12px literal.
    assert_includes css, "calc(var(--chrome-inset) + var(--safe-top))"
  end

  def test_dialect_exports_family_chrome_vars
    scss = File.read(DIALECT)
    assert_includes scss, "--chrome-inset: 0.75rem"
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
