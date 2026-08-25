# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class ModelSingleLlmCallTest < Minitest::Test
  # Scoped to the class. At top level this was the third `ROOT` in one test
  # process — test_no_lib_backedges.rb defines the same Pathname, and
  # STUDIO/dilla/dilla.rb defines a String. Load order decided which won, so
  # this test passed alone and died on `undefined method 'join' for a String`
  # in the full run.
  ROOT = Pathname.new(__dir__).join("..", "..").expand_path

  def test_model_rb_has_one_llm_ask_site
    path = ROOT.join("lib", "core", "model.rb")
    text = path.read
    ask_sites = text.each_line.with_index(1).select { |line, _| line.include?(".ask(") }
    assert_equal 1, ask_sites.size,
                 "lib/core/model.rb must have exactly one .ask( call site (M6):\n" \
                 "#{ask_sites.map { |l, n| "#{path}:#{n}: #{l.strip}" }.join("\n")}"
    refute_match(/\brescue\b(?!\s+StandardError|\s+JSON::)/, text.gsub(/#.*$/, ""),
                 "lib/core/model.rb must not use bare rescue (M8)")
  end
end
