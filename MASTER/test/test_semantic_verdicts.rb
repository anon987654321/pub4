# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/master"
require_relative "../lib/fix/scan/semantic_verdicts"

class TestSemanticVerdicts < Minitest::Test
  Law = Struct.new(:id)

  def setup
    @dir = Dir.mktmpdir
    @laws = [Law.new("B"), Law.new("A")]
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def verdicts = Master::Fix::Scan::SemanticVerdicts.new(root: @dir)

  def test_a_recorded_clean_file_is_clean_until_it_changes
    verdicts.record("a.rb", code: "puts 1\n", laws: @laws)
    fresh = verdicts

    assert fresh.clean?("a.rb", code: "puts 1\n", laws: @laws)
    refute fresh.clean?("a.rb", code: "puts 2\n", laws: @laws)
  end

  def test_a_changed_law_set_asks_again
    verdicts.record("a.rb", code: "puts 1\n", laws: @laws)

    refute verdicts.clean?("a.rb", code: "puts 1\n", laws: @laws + [Law.new("C")])
    assert verdicts.clean?("a.rb", code: "puts 1\n", laws: @laws.reverse)
  end

  def test_an_unknown_file_is_not_clean
    refute verdicts.clean?("b.rb", code: "x", laws: @laws)
  end
end
