# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

ROOT = Pathname.new(__dir__).join("..", "..").expand_path

class ModelSingleLlmCallTest < Minitest::Test
  def test_model_rb_has_one_llm_ask_site
    path = ROOT.join("core", "model.rb")
    text = path.read
    ask_sites = text.each_line.with_index(1).select { |line, _| line.include?(".ask(") }
    assert_equal 1, ask_sites.size,
                 "core/model.rb must have exactly one .ask( call site (M6):\n" \
                 "#{ask_sites.map { |l, n| "#{path}:#{n}: #{l.strip}" }.join("\n")}"
    refute_match(/\brescue\b(?!\s+StandardError|\s+JSON::)/, text.gsub(/#.*$/, ""),
                 "core/model.rb must not use bare rescue (M8)")
  end
end
