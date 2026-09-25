# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# The two MASTER/tools vocab-checks are the real contract for postpro and preprompt.
# They used to be operator memory. A table that fails quiet is how unread
# temp: and a costume --final model survive.
class TestToolsMedia < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  POSTPRO = File.join(ROOT, "MASTER/tools", "postpro", "postpro.rb")
  PREPROMPT = File.join(ROOT, "MASTER/tools", "preprompt", "preprompt.rb")

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
      require File.join(ROOT, "MASTER/tools", "dilla", "lib", "engine_sources")
      DillaSources.all.map { |path| File.read(path) }.join("\n")
    end
  end

  def test_postpro_finishing_grain_uses_the_preset_stock
    source = File.read(POSTPRO)
    assert_includes source, "def apply_finishing_grain"
    assert_includes source, "GRAIN_REFERENCE_WIDTH"
    refute_match(/grain\(processed, 400, :kodak_portra, 0\.35\)/, source)
    # Reaching the pass is the invariant; naming it is one way to reach it. Two
    # spellings have already been asserted here and both went stale while the
    # behaviour stayed right: the verbatim call site, which run_random replaced
    # with process_file, then process_file itself, which run_watch replaced with
    # grade_watched. So the assertion follows calls instead of naming the hop.
    %w[process_file run_random run_uplift run_one_shot run_watch].each do |name|
      assert source.match?(/^def #{name}\b/), "#{name} must still exist"
      assert reaches?(source, name, "apply_finishing_grain"),
             "#{name} must reach apply_finishing_grain, through however many helpers it calls"
    end
  end

  # Whether one top-level method of a single-file script reaches another, by
  # following the names it calls. Shallow on purpose: it reads call spellings in
  # a body, so a dynamic send is invisible to it — postpro has none on this path,
  # and a reachability check that tried to be exact would be a second interpreter.
  def reaches?(source, from, target, seen = [])
    return false if seen.include?(from)

    body = source[/^def #{from}\b.*?^end$/m]
    return false unless body
    return true if body.include?(target)

    body.scan(/\b([a-z_][a-z0-9_]*)\(/).flatten.uniq
        .any? { |callee| reaches?(source, callee, target, seen + [from]) }
  end

  # The model string is not the invariant. This pinned flux-1.1-pro-ultra and
  # went red the day 495bb98d8 made FLUX 2 the default — a deliberate upgrade
  # the test read as a regression, which is what a version literal in an
  # assertion always ends up doing. What has to hold is that FINAL_MODEL names a
  # model preprompt actually knows, and vocab-check is the check that proves it:
  # preprompt.rb refuses a FINAL_MODEL with no MODEL_CAPABILITIES entry.
  def test_preprompt_vocab_check_exits_zero_and_final_model_is_known
    out, status = run_script(PREPROMPT, "vocab-check")
    assert status.success?, "preprompt vocab-check failed:\n#{out}"

    source = File.read(PREPROMPT)
    final = source[/^FINAL_MODEL = "([^"]+)"/, 1]
    assert final, "preprompt must declare a FINAL_MODEL"
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
