# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/scan/rule_dsl"

# RuleLoop asks for one corrected file per answer. Splitting a 1,018-line
# Rakefile needs new files, so Opus answered UNCHANGED twice after an
# architecture plan, three model calls for nothing on every oversized file.
# A finding whose repair spans files says so, and waits for a person.
class TestSplitFindingsNeedAPerson < Minitest::Test
  Rules = Master::Review::Scan::Rules

  def needs_a_person?(finding)
    violation = Master::Fix::Violation.from_finding(finding.to_h, file: "example.rb").to_h
    Master::Fix::RuleLoop.allocate.send(:needs_a_person?, violation)
  end

  def test_an_oversized_file_is_a_person_s_split
    finding = Rules::SmallFilesRule.new.check("x = 1\n" * 400, path: "/repo/lib/big.rb").first

    assert needs_a_person?(finding)
  end

  def test_flattening_a_data_file_is_a_person_s_change
    deep = "a:\n  b:\n    c:\n      d:\n        e:\n          f: 1\n"
    finding = Rules::ConfigHierarchyRule.new.check(deep, path: "/repo/data/deep.yml").first

    assert needs_a_person?(finding)
  end

  def test_a_one_file_repair_still_goes_to_the_model
    finding = Rules::CouplerRule.new.check("order.send(:recalculate)\n", path: "/repo/lib/a.rb").first

    refute needs_a_person?(finding)
  end
end
