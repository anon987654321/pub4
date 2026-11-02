# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../MASTER/tools/rails/layout_drift_audit"

class LayoutDriftAuditTest < Minitest::Test
  def audit
    @audit ||= Operator::LayoutDriftAudit.new(root: Dir.tmpdir)
  end

  def test_feed_list_scanner_masks_erb_output_before_finding_tag_end
    source = <<~ERB
      <ul role="list" class="feed_list<%= size > 1 ? " feed-grid" : "" %>">
        <li>one</li>
      </ul>
    ERB

    tags = audit.feed_list_open_tags(source)

    assert_equal 1, tags.length
    assert_match(/role="list"/, tags.first)
    assert_match(/feed_list/, tags.first)
  end

  def test_feed_list_scanner_reports_missing_list_role
    source = '<ul class="feed_list"><li>one</li></ul>'

    assert_equal 1, audit.feed_list_violations(source).length
  end

  def test_feed_list_scanner_accepts_role_before_dynamic_attributes
    source = '<ul role="list" class="feed_list<%= dynamic_class %>">'

    assert_empty audit.feed_list_violations(source)
  end

  def test_only_real_post_list_items_receive_block_boxes
    css = <<~SCSS
      .feed_list > li { display: contents; }
      .feed_list.post-card-list > li {
        display: block;
        min-inline-size: 0;
      }
    SCSS

    assert_includes css, ".feed_list.post-card-list > li"
    assert_match(/\.feed_list\.post-card-list > li\s*\{\s*display:\s*block;/, css)
  end

  def test_report_marks_browser_and_runtime_evidence_as_not_run
    Dir.mktmpdir do |root|
      report = Operator::LayoutDriftAudit.new(root:)
      report.run

      assert_includes report.findings.map(&:code), "rendered_visual"
      assert_includes report.findings.map(&:code), "runtime_suites"
      assert_equal 2, report.findings.count { |finding| finding.status == "NOT_RUN" }
    end
  end
end
