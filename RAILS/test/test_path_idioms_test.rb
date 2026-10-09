# frozen_string_literal: true

require "minitest/autorun"

# Two path habits passed in the repo and failed in the box's copy-tree, where
# the app is /home/brgen/app (not RAILS/brgen) and the vertical engines sit
# beside it as brgen_*:
#
#   1. a path guessed with File.expand_path("../..", __dir__) that names a
#      `brgen` directory, which is "app" on the box;
#   2. a read of `engines/<vertical>/` under the app root, when the engines
#      live in sibling brgen_* directories (Rails.root/../brgen_x works in both).
#
# This scan reads source only, so it needs no Rails boot.
class TestPathIdiomsTest < Minitest::Test
  RAILS_ROOT = File.expand_path("..", __dir__)
  FILES = Dir.glob(File.join(RAILS_ROOT, "*", "test", "**", "*.rb")).reject { |f| f == __FILE__ }.freeze

  def offences(pattern)
    FILES.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, i|
        next if line.lstrip.start_with?("#")

        "#{file.delete_prefix("#{RAILS_ROOT}/")}:#{i + 1}: #{line.strip}" if line.match?(pattern)
      end
    end
  end

  def test_scan_sees_the_test_files
    assert_operator FILES.size, :>, 50
  end

  def test_no_path_is_guessed_through_a_brgen_directory_name
    found = offences(%r{expand_path\([^)]*\.\./[^)]*\bbrgen/})
    assert_empty found, "build app paths from Rails.root, not from a `brgen` directory name:\n#{found.join("\n")}"
  end

  def test_no_test_reads_engines_under_the_app_root
    found = offences(%r{["']engines/(?:tv|takeaway|dating|playlist|marketplace|maps|radio)\b})
    assert_empty found, "engines are sibling brgen_* directories; use Rails.root.join(\"..\", \"brgen_x\", ...):\n#{found.join("\n")}"
  end
end
