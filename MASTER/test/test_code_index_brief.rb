# frozen_string_literal: true

require_relative "test_helper"

# The prompt carried the whole repo's class listing (~290 KB) on every model
# call. The brief is bounded: orientation always, plus the slice the turn names.
class TestCodeIndexBrief < Minitest::Test
  def with_index(extra: 0)
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      Dir.mkdir(File.join(root, "lib"))
      File.write(File.join(root, "lib", "widget_maker.rb"), "module Shop\n  class WidgetMaker\n  end\nend\n")
      extra.times { |n| File.write(File.join(root, "lib", "filler_#{n}.rb"), "class FillerThing#{n}\nend\n") }
      yield Master::Review::CodeIndex.new(root:).build
    end
  end

  def test_unrelated_turn_gets_only_the_orientation
    with_index(extra: 40) do |index|
      text = index.summary(focus: "hello, how are you today")
      assert_includes text, "# Codebase:"
      assert_includes text, "symbol_lookup"
      refute_includes text, "WidgetMaker"
      refute_includes text, "FillerThing"
    end
  end

  def test_a_named_constant_gets_its_slice
    with_index do |index|
      text = index.summary(focus: "why does WidgetMaker fail?")
      assert_includes text, "## Named in this turn"
      assert_includes text, "Shop::WidgetMaker (lib/widget_maker.rb:2)"
    end
  end

  def test_a_named_file_gets_its_slice
    with_index do |index|
      assert_includes index.summary(focus: "open lib/widget_maker.rb"), "Shop::WidgetMaker"
    end
  end

  def test_size_stays_bounded_however_large_the_index
    with_index(extra: 400) do |index|
      names = (0...400).map { |n| "FillerThing#{n}" }.join(" ")
      assert_operator index.summary(focus: names).bytesize, :<, 5_000
      assert_operator index.summary.bytesize, :<, 1_000
    end
  end

  def test_the_prompt_asks_the_index_for_the_turn_it_is_answering
    source = File.read(File.join(Master::ROOT, "lib/review/agent/prompt_builder.rb"))
    assert_includes source, "@code_index.summary(focus: last_user_message)"
  end
end
