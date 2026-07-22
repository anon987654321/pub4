# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/scan/rules/structural_rules"

class TestLibRootDisciplineRule < Minitest::Test
  # "core stays lean" as a live check (OpenClaw's VISION.md policy) -- new
  # files shouldn't land directly in lib/ root without a deliberate,
  # visible decision (adding to ALLOWED_ROOT_FILES).
  def setup
    @rule = Master::Review::Scan::Rules::LibRootDisciplineRule.new(root: Master::ROOT)
  end

  def test_flags_a_new_file_directly_in_lib_root
    path = File.join(Master::ROOT, "lib", "some_new_thing.rb")
    findings = @rule.check("", path:)

    assert_equal 1, findings.size
    assert_match(/lib\/ root/, findings.first.message)
  end

  def test_allows_known_core_files_in_lib_root
    path = File.join(Master::ROOT, "lib", "master.rb")

    assert_empty @rule.check("", path:)
  end

  def test_ignores_files_in_subdirectories
    path = File.join(Master::ROOT, "lib", "fix", "rule_loop.rb")

    assert_empty @rule.check("", path:)
  end

  def test_ignores_non_ruby_files_in_lib_root
    path = File.join(Master::ROOT, "lib", "README.md")

    assert_empty @rule.check("", path:)
  end
end
