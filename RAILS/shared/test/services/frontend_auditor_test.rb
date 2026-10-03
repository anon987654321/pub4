# frozen_string_literal: true

require "minitest/autorun"
require "active_support/core_ext/array"
require "pathname"
require "tmpdir"
require_relative "../../app/services/shared/frontend_auditor"

class FrontendAuditorTest < Minitest::Test
  def test_flags_inline_style_attributes_in_views
    Dir.mktmpdir do |tmpdir|
      view = Pathname(tmpdir).join("app/views/posts/show.html.erb")
      view.dirname.mkpath
      view.write('<div style="color: red">x</div>')

      findings = Shared::FrontendAuditor.call(root: tmpdir)

      assert findings.any? { |finding| finding.rule == :inline_style_attr && finding.severity == :warning }
    end
  end

  def test_allows_views_without_inline_styles
    Dir.mktmpdir do |tmpdir|
      view = Pathname(tmpdir).join("app/views/posts/show.html.erb")
      view.dirname.mkpath
      view.write('<div class="card">x</div>')

      findings = Shared::FrontendAuditor.call(root: tmpdir)

      assert findings.none? { |finding| finding.rule == :inline_style_attr }
    end
  end

  def test_skips_mailer_layout_inline_styles
    Dir.mktmpdir do |tmpdir|
      view = Pathname(tmpdir).join("app/views/layouts/mailer.html.erb")
      view.dirname.mkpath
      view.write("<style>body { margin: 0; }</style>")

      findings = Shared::FrontendAuditor.call(root: tmpdir)

      assert findings.none? { |finding| finding.rule == :inline_css }
    end
  end

  def test_skips_vendor_paths
    Dir.mktmpdir do |tmpdir|
      view = Pathname(tmpdir).join("vendor/bundle/gem/app/views/posts/show.html.erb")
      view.dirname.mkpath
      view.write('<div style="color: red">x</div>')

      findings = Shared::FrontendAuditor.call(root: tmpdir)

      assert findings.empty?
    end
  end

  def test_allows_css_custom_property_inline_styles
    Dir.mktmpdir do |tmpdir|
      view = Pathname(tmpdir).join("app/views/compare/_bar.html.erb")
      view.dirname.mkpath
      view.write('<div class="thread-bar" style="--bar-width: 72%"></div>')

      findings = Shared::FrontendAuditor.call(root: tmpdir)

      assert findings.none? { |finding| finding.rule == :inline_style_attr }
    end
  end

  def test_flags_block_elements_nested_in_paragraphs
    assert_view_rule('<p><div class="field">x</div></p>', :invalid_paragraph_block)
  end

  def test_flags_empty_landmarks
    assert_view_rule('<nav aria-label="Actions"></nav>', :empty_landmark)
  end

  def test_flags_main_landmarks_in_regular_views
    assert_view_rule("<main><h1>Nested</h1></main>", :nested_main)
  end

  def test_flags_duplicate_turbo_cache_control_directives
    assert_view_rule(<<~HTML, :duplicate_turbo_cache_control, layout: true)
      <a href="#main-content">Skip</a>
      <meta name="turbo-cache-control" content="no-preview">
      <meta name="turbo-cache-control" content="no-cache">
      <main id="main-content"></main>
    HTML
  end

  def test_product_pen_stylesheets_are_info_only
    Dir.mktmpdir do |tmpdir|
      pen = Pathname(tmpdir).join("app/assets/stylesheets/_search_yep.scss")
      pen.dirname.mkpath
      pen.write(<<~SCSS)
        .search { box-shadow: 0 0 10px #000; left: 0; font-size: 8px; }
        .a.b.c.d { color: red; }
      SCSS

      findings = Shared::FrontendAuditor.call(root: tmpdir)
      pen_findings = findings.select { |f| f.path.to_s.end_with?("_search_yep.scss") }

      assert pen_findings.any? { |f| f.rule == :product_pen && f.severity == :info }
      assert pen_findings.none? { |f| f.severity == :warning || f.severity == :error },
             "pen CSS must not hygiene-fail: #{pen_findings.map { |f| [ f.severity, f.rule ] }.inspect}"
    end
  end

  private

  def assert_view_rule(contents, rule, layout: false)
    Dir.mktmpdir do |tmpdir|
      relative = layout ? "app/views/layouts/application.html.erb" : "app/views/posts/show.html.erb"
      view = Pathname(tmpdir).join(relative)
      view.dirname.mkpath
      view.write(contents)

      findings = Shared::FrontendAuditor.call(root: tmpdir)

      assert findings.any? { |finding| finding.rule == rule && finding.severity == :warning }
    end
  end
end
