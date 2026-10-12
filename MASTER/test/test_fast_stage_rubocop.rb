# frozen_string_literal: true

require_relative "test_helper"

class TestFastStageRubocop < Minitest::Test
  class Harness
    include Master::Fix::FixLoop::PassRunner::FastStage

    def initialize(root) = @root = root
    def stuck(out, _files) = uncorrected_files(JSON.parse(out).fetch("files"), @root)
  end

  ROOT = "/repo/MASTER"

  def report(*entries) = JSON.generate("files" => entries)

  def test_a_file_whose_offenses_were_all_corrected_is_not_stuck
    out = report(
      { "path" => "lib/a.rb", "offenses" => [{ "corrected" => true }] },
      { "path" => "lib/b.rb", "offenses" => [] },
    )

    assert_empty Harness.new(ROOT).stuck(out, [])
  end

  def test_a_file_with_one_uncorrected_offense_is_stuck
    out = report(
      { "path" => "lib/a.rb", "offenses" => [{ "corrected" => true }, { "corrected" => false }] },
      { "path" => "lib/b.rb", "offenses" => [{ "corrected" => true }] },
    )

    assert_equal ["#{ROOT}/lib/a.rb"], Harness.new(ROOT).stuck(out, [])
  end
end
