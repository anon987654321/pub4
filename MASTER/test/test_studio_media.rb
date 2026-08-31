# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# The two STUDIO vocab-checks are the real contract for postpro and repligen.
# They used to be operator memory. A table that fails quiet is how unread
# temp: and a costume --final model survive.
class TestStudioMedia < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  POSTPRO = File.join(ROOT, "STUDIO", "postpro", "postpro.rb")
  REPLIGEN = File.join(ROOT, "STUDIO", "repligen", "repligen.rb")

  def test_postpro_unread_temp_is_a_vocab_check_error
    source = File.read(POSTPRO)
    assert_match(/temp:\s*%w\[spectral_temp color_temp\]/, source,
                 "temp: must sit in key_readers next to stops:/lens:/age:, not in a NOTE")
    refute_match(/deliberately not fatal/, source)

    # Every preset that sets temp: has to name a step that reads it. Parsed
    # from the table rather than by booting postpro: ruby-vips is not in
    # MASTER's bundle, and `bundle exec rake test` is how this file runs.
    source.scan(/^  ([a-z0-9_]+): \{ fx: %w\[([^\]]+)\]([^}]*)\}/m).each do |name, fx, rest|
      next unless rest.match?(/\btemp:/)
      assert(fx.split.intersect?(%w[spectral_temp color_temp]),
             "#{name} sets temp: but its chain has no spectral_temp/color_temp step")
    end
  end

  # DillaSources, not a hand-spelled path: lib/engine/grade_analog.rb and
  # lib/engine/tape_master.rb stopped existing when the engine collapsed back
  # into dilla.rb plus lib/*.rb, and this test failed for the layout rather
  # than for the claim it makes.
  def test_sonitex_sections_cover_the_stx1260_and_default_to_the_preset
    engine = dilla_engine_source
    assert_includes engine, "SONITEX_SECTIONS"
    assert_includes engine, "sonitex_section_amount"
    %w[mix distortion vinyl tone noise sampling].each do |section|
      assert_match(/^\s+#{section}:/, engine)
    end
    assert_includes engine, "def params_for_bias"
    assert_includes engine, "TAPE_BIAS"
    assert_includes engine, "TAPE_LOSS_HZ"
  end

  # Every file the engine is made of, concatenated — the same corpus the
  # engine's own parse check and provenance manifest read.
  def dilla_engine_source
    @dilla_engine_source ||= begin
      require File.join(ROOT, "STUDIO", "dilla", "lib", "engine_sources")
      DillaSources.all.map { |path| File.read(path) }.join("\n")
    end
  end

  def test_postpro_finishing_grain_uses_the_preset_stock
    source = File.read(POSTPRO)
    assert_includes source, "def apply_finishing_grain"
    assert_includes source, "GRAIN_REFERENCE_WIDTH"
    refute_match(/grain\(processed, 400, :kodak_portra, 0\.35\)/, source)
    %w[process_file run_random run_one_shot run_watch].each do |name|
      body = source[/^def #{name}\b.*?^end$/m]
      assert body, "#{name} must still exist"
      assert_includes body, "apply_finishing_grain(processed",
                      "#{name} must finish through apply_finishing_grain, not a hardcoded Portra pass"
    end
  end

  # The model string is not the invariant. This pinned flux-1.1-pro-ultra and
  # went red the day 495bb98d8 made FLUX 2 the default — a deliberate upgrade
  # the test read as a regression, which is what a version literal in an
  # assertion always ends up doing. What has to hold is that FINAL_MODEL names a
  # model repligen actually knows, and vocab-check is the check that proves it:
  # repligen.rb refuses a FINAL_MODEL with no MODEL_CAPABILITIES entry.
  def test_repligen_vocab_check_exits_zero_and_final_model_is_known
    out, status = run_script(REPLIGEN, "vocab-check")
    assert status.success?, "repligen vocab-check failed:\n#{out}"

    source = File.read(REPLIGEN)
    final = source[/^FINAL_MODEL = "([^"]+)"/, 1]
    assert final, "repligen must declare a FINAL_MODEL"
    assert_includes source, %("#{final}"), "FINAL_MODEL #{final} has no entry beside it"
    assert_includes source, '"black-forest-labs/flux-kontext-pro"'
    assert_includes source, "input_image"
    assert_includes source, '"raw"'
  end

  def run_script(script, *args)
    # These scripts install and load their own gems (ruby-vips). `bundle exec`
    # rake test leaves BUNDLE_* set, so a require "vips" looks in MASTER's
    # Gemfile and misses the gem postpro just installed. Operator invocations
    # are plain `ruby`, so the test has to be too.
    env = ENV.to_h.reject { |key, _| key.start_with?("BUNDLE_") }
    env["RUBYOPT"] = env["RUBYOPT"].to_s.split.reject { |flag| flag.include?("bundler") }.join(" ")
    out, status = Open3.capture2e(env, RbConfig.ruby, script, *args)
    [out, status]
  end
end
