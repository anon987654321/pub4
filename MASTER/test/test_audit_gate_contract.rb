# frozen_string_literal: true

require_relative "test_helper"

class TestAuditGateContract < Minitest::Test
  def setup
    @rakefile = File.read(File.join(Master::ROOT, "Rakefile"))
    @checks = @rakefile[/^AUDIT_CHECKS = %w\[\s*(.*?)\s*\]\.freeze/m, 1]&.split
  end

  def test_every_defined_lint_is_part_of_the_full_audit_gate
    lint_section = @rakefile[/namespace :lint do\n(.*?)\nend\n\n# Every check this Rakefile defines runs here\./m, 1]
    tool_lints = @rakefile[/TOOL_LINT_TASKS = \{(.*?)\}\.freeze/m, 1]

    refute_nil @checks, "Rakefile must declare the full audit gate"
    refute_nil lint_section, "Rakefile must declare the lint namespace"
    refute_nil tool_lints, "Rakefile must declare the tool-lint inventory"

    standalone = lint_section.scan(/^\s*task\s+:(\w+)/).flatten.map { |name| "lint:#{name}" }
    generated = tool_lints.scan(/^\s{4}(\w+):\s*\[/).flatten.map { |name| "lint:#{name}" }
    missing = (standalone + generated).uniq - @checks

    assert_empty missing,
                 "defined lint tasks omitted from AUDIT_CHECKS never run during rake audit: #{missing.join(', ')}"
  end

  def test_law_trace_loads_the_canonical_detector_registry
    task = @rakefile[/task :law_trace do\n(.*?)\n  end/m, 1]

    refute_nil task, "Rakefile must define lint:law_trace"
    assert_includes task, 'require "review/scan/law_tree"',
                  "the canonical DSL loader imports detector implementations from MASTER/law"
    refute_match(%r{lib/review/scan/laws}, task,
                 "the deleted compatibility path must not be a loader input")
  end

  def test_runtime_contract_and_boot_smokes_are_part_of_the_full_audit_gate
    %w[selfcheck architecture boot_smoke].each do |name|
      assert_includes @checks, name, "#{name} is a declared non-model check but is omitted from AUDIT_CHECKS"
    end
  end
end
