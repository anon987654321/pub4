# frozen_string_literal: true

require_relative "test_helper"
require "ruby_llm"
require "tmpdir"
require_relative "../lib/io/ruby_llm_patch"

# lib/io/ruby_llm_patch.rb builds a Model::Info for ids the shipped registry
# does not carry. A key the gem's constructor never reads sets nothing, so the
# fallback must pass only keys Model::Info#initialize actually looks up — and
# that set belongs to the installed gem, so it is measured, not listed.
class TestRubyLlmPatch < Minitest::Test
  # Records every key the constructor asks for.
  class KeyProbe < Hash
    attr_reader :asked

    def [](key)
      (@asked ||= []) << key
      super
    end
  end

  def fallback_arguments
    captured = nil
    original = RubyLLM::Model::Info.method(:new)
    RubyLLM::Model::Info.stub(:new, ->(data) { captured = data; original.call(data) }) do
      RubyLLM::Models.allocate.send(:fallback_model_info, "vendor/unknown-model")
    end
    captured
  end

  def test_the_fallback_passes_only_keys_the_gem_reads
    probe = KeyProbe.new
    RubyLLM::Model::Info.new(probe)

    unread = fallback_arguments.keys - probe.asked
    assert_empty unread, "Model::Info#initialize never reads #{unread.join(', ')}"
  end

  def test_an_unknown_id_resolves_to_an_openrouter_model_instead_of_raising
    info = RubyLLM::Models.allocate.send(:fallback_model_info, "vendor/unknown-model")

    assert_equal "vendor/unknown-model", info.id
    assert_equal "openrouter", info.provider
    assert_equal "vendor", info.family
    assert_equal 128_000, info.context_window
  end

  # The encoding: argument exists because vm23's cron and rc.d run with no
  # locale, so the default external encoding is US-ASCII.
  def test_the_registry_reads_as_utf8_under_an_ascii_locale
    Dir.mktmpdir do |dir|
      path = File.join(dir, "models.json")
      File.write(path, JSON.generate([{ id: "a/b", name: "Café — model", provider: "openrouter" }]), encoding: "UTF-8")
      previous = Encoding.default_external
      silence_warnings { Encoding.default_external = Encoding::US_ASCII }

      models = RubyLLM::Models.read_from_json(path)

      assert_equal ["Café — model"], models.map(&:name)
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
