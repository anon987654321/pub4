# frozen_string_literal: true

require_relative "test_helper"
require "ruby_llm"
require "tmpdir"
require_relative "../lib/io/ruby_llm_patch"

# lib/io/ruby_llm_patch.rb keeps one thing from RubyLLM 1 (00aae8664): an id
# the registry does not carry resolves to an OpenRouter model instead of
# raising, and an id it does carry still resolves to its registry entry.
# RubyLLM 2 owns registry loading and its UTF-8 decoding; the last test holds
# the gem to the vm23 locale MASTER runs under.
class TestRubyLlmPatch < Minitest::Test
  def test_an_unknown_id_resolves_to_an_openrouter_model_instead_of_raising
    info = RubyLLM.models.find("vendor/unknown-model")

    assert_equal "vendor/unknown-model", info.id
    assert_equal "openrouter", info.provider
  end

  def test_a_registry_id_resolves_to_its_registry_entry
    known = RubyLLM.models.all.first

    assert_same known, RubyLLM.models.find(known.id)
  end

  # vm23's cron and rc.d run with no locale, so the default external
  # encoding is US-ASCII.
  def test_the_registry_reads_as_utf8_under_an_ascii_locale
    Dir.mktmpdir do |dir|
      path = File.join(dir, "models.json")
      File.write(path, JSON.generate([{ id: "a/b", name: "Café — model", provider: "openrouter" }]), encoding: "UTF-8")
      previous = Encoding.default_external
      silence_warnings { Encoding.default_external = Encoding::US_ASCII }

      models = RubyLLM::Models.new.load_from_json(path)

      assert_equal "Café — model", models.find("a/b").name
    ensure
      silence_warnings { Encoding.default_external = previous }
    end
  end

  private

  def silence_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
