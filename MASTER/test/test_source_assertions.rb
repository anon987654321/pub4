# frozen_string_literal: true

require_relative "test_helper"

# A test that reads a source file and greps it is a category error.
#
# It asserts that a method is *spelled* a certain way, not that it *does*
# anything: gut every body in lib/boot/runtime.rb and spec/ops/boot_safety_spec.rb
# stays green, while renaming a constant fails it with the behaviour intact. The
# file that claims to cover "MASTER never starts a background loop unless asked"
# is twenty of these in a row.
#
# It is not always wrong. Asserting that a generated file contains its banner,
# or that a manifest lists what it must list, is a genuine text property. So
# this is a ratchet rather than a ban: the number may fall and may not rise, and
# each fall is a test that started calling the thing it describes.
#
# Measured 2026-08-23: 231 across 42 files, then 228 when
# spec/ops/source_loop_guards_spec.rb stopped grepping for its guards and
# started calling them. The worst concentrations are
# test_web_ui.rb (41), spec/tools/lifecycle_tools_spec.rb (17) and
# spec/ops/boot_safety_spec.rb (16, the whole file).
class TestSourceAssertions < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BASELINE = 223

  # An assertion whose subject is the text of a file rather than a value the
  # code produced. `source`, `src` and `body` are this repo's names for that
  # text; File.read inline is the same thing written out.
  PATTERN = /assert_(?:includes|match|no_match)\b[^\n]*\b(?:source|src|body|read|File\.read)\b/

  def self.occurrences
    Dir.glob(File.join(ROOT, "{test,spec}", "**", "*.rb")).sort.flat_map do |path|
      rel = path.sub("#{ROOT}/", "")
      next [] if rel == "test/test_source_assertions.rb"

      File.readlines(path).each_with_index.filter_map do |line, i|
        "#{rel}:#{i + 1}" if line.match?(PATTERN)
      end
    end
  end

  def test_source_text_assertions_only_ever_decrease
    found = self.class.occurrences

    assert_operator found.size, :<=, BASELINE,
                    "source-text assertions rose to #{found.size} (baseline #{BASELINE}). " \
                    "A test that greps a source file passes against a body of `raise`. " \
                    "Assert what the code does:\n  #{(found.first(10)).join("\n  ")}"
  end

  # The half that keeps a ratchet honest. A floor nobody lowers stops being a
  # floor, and this repo has watched exactly that happen to two other counters.
  def test_a_beaten_baseline_is_recorded
    found = self.class.occurrences

    assert_operator found.size, :>=, BASELINE,
                    "source-text assertions fell to #{found.size} — lower BASELINE to match, " \
                    "so the gain cannot be given back silently."
  end
end
