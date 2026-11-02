# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../tools/empty_state_lint"

class EmptyStateLintTest < Minitest::Test
  Lint = Operator::EmptyStateLint

  def findings_for(render)
    Dir.mktmpdir("empty-state-lint") do |root|
      path = File.join(root, "index.html.erb")
      File.write(path, render)
      Lint.stub(:view_files, [path]) { Lint.action_findings }
    end
  end

  def test_legacy_actions_local_is_a_blocking_ratchet_finding
    findings = findings_for(<<~ERB)
      <%= render "shared/empty_state",
                 title: "No items", actions: "Browse items" %>
    ERB

    assert_equal ["legacy_actions"], findings.map(&:kind)
  end

  def test_hash_action_is_accepted
    findings = findings_for(<<~ERB)
      <%= render "shared/empty_state",
                 title: "No items", action: { label: "Browse", path: items_path } %>
    ERB

    assert_empty findings
  end

  def test_missing_action_remains_a_separate_finding
    findings = findings_for('<%= render "shared/empty_state", title: "No items" %>')

    assert_equal ["missing_action"], findings.map(&:kind)
  end
end
