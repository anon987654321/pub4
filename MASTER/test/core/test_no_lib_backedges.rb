# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

ROOT = Pathname.new(__dir__).join("..", "..").expand_path
CORE = ROOT.join("core")
LIB = ROOT.join("lib")

class NoLibBackedgesTest < Minitest::Test
  def test_core_files_do_not_require_lib
    offenders = []
    CORE.glob("**/*.rb").each do |path|
      text = path.read
      next unless text.match?(/\b(require|require_relative)\b/)

      text.each_line.with_index(1) do |line, lineno|
        next unless line.match?(/\b(require|require_relative)\s+["'].*lib/)

        offenders << "#{path.relative_path_from(ROOT)}:#{lineno}: #{line.strip}"
      end
    end

    assert_empty offenders, "core/ must not require lib/:\n#{offenders.join("\n")}"
  end
end