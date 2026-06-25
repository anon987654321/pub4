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
end