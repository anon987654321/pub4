# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/sprawl_census"
require_relative "../lib/fix/rename_sweep"
require_relative "../lib/review/scan/law_dsl"

# data/vague_words.yml is the one vague-name list; four readers had a copy each
# and no two agreed. Every reader takes every word, and none keeps a word of its own.
class TestVagueWords < Minitest::Test
  WORDS = Master::Ground::ParameterizedSlug::VAGUE_WORDS

  def vague_law
    laws = Master::Review::Scan::Law.registry
    laws.find { |klass| klass.instance_variable_get(:@dsl_id) == "FILE_VAGUE_NAME" }.new
  end

  def test_the_list_is_read_from_data
    refute_empty WORDS
    assert_equal WORDS, Master.load_yaml(Master::Ground::ParameterizedSlug::VAGUE_WORDS_PATH).fetch("words")
  end

  def test_every_reader_takes_every_word
    assert_equal WORDS, Operator::SprawlCensus::VAGUE
    WORDS.each do |word|
      assert_match Master::Fix::RenameSweep::SUSPECT, "#{word}_report", word
      assert_includes Master::Ground::ParameterizedSlug::FILLER_TOKENS, word
      refute_empty vague_law.check("", path: "/repo/lib/#{word}_report.rb"), word
    end
  end

  def test_a_word_left_out_is_left_out_everywhere
    refute_includes Operator::SprawlCensus::VAGUE, "base"
    refute_match Master::Fix::RenameSweep::SUSPECT, "base_report"
    refute_includes Master::Ground::ParameterizedSlug::FILLER_TOKENS, "base"
    assert_empty vague_law.check("", path: "/repo/app/controllers/maps/base_controller.rb")
  end
end
