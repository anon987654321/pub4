# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# The two MASTER/tools vocab-checks are the real contract for postpro and replicate.
# They used to be operator memory. A table that fails quiet is how unread
# temp: and a costume --final model survive.
class TestToolsMedia < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  POSTPRO = File.join(ROOT, "MASTER/tools", "postpro", "postpro.rb")
  REPLICATE = File.join(ROOT, "MASTER/tools", "replicate", "replicate.rb")

  def test_postpro_key_readers_cover_every_declared_preset_knob
    source = File.read(POSTPRO)
    expected = {
      "stops" => %w[push_pull],
      "age" => %w[faded_print dye_fade expired_film],
      "print_stock" => %w[print_film],
      "exposure_secs" => %w[reciprocity_failure],
      "k1" => %w[lens_distortion],
      "f_number" => %w[diffraction_blur],
      "tonemap_ev" => %w[tonemap],
      "temp" => %w[spectral_temp color_temp],
      "tonemap" => %w[tonemap],
      "azimuth" => %w[relight],
      "shape" => %w[relight]
    }

    reader_source = source[/key_readers = \{(.*?)^  \}/m, 1]
    assert reader_source, "postpro must define its preset key-reader contract"
    actual = reader_source.scan(/([a-z_][a-z0-9_]*):\s*%w\[([^\]]+)\]/)
                          .to_h { |key, readers| [key, readers.split] }
    assert_equal expected, actual, "every operator-set preset knob needs one declared reader"

    presets = source.scan(/^  ([a-z0-9_]+): \{ fx: %w\[([^\]]+)\]([^}]*)\}/m)
    assert_operator presets.size, :>, 0, "preset scanner must reach the source table"
    expected.each do |key, readers|
      matching = presets.select { |_, _, rest| rest.match?(/\b#{Regexp.escape(key)}:/) }
      assert_operator matching.size, :>, 0, "preset scanner must see declarations of #{key}:"
      matching.each do |name, fx, _rest|
        assert(fx.split.intersect?(readers),
               "#{name} declares #{key}: but its chain has no #{readers.join('/')} reader")
      end
    end
  end

  def test_postpro_rejects_unknown_presets_instead_of_silently_returning_the_input
    source = File.read(POSTPRO)
    body = method_body(source, "preset")

    assert body, "preset resolver must exist"
    assert_match(/raise ArgumentError, "unknown preset/, body)
    refute_match(/return image unless p/, body)
  end

  def test_method_body_reader_includes_calls_after_nested_blocks
    source = File.read(POSTPRO)

    assert_includes method_body(source, "run_random"), "process_file("
    assert_includes method_body(source, "run_watch"), "grade_watched("
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

  # Read through the next top-level method, not the first nested `end`.
  # These checks inspect source contracts, so truncating an inner if/loop must
  # not turn a reachable call into a false negative.
  def method_body(source, name)
    pattern = Regexp.new("^def " + Regexp.escape(name) + "\\b.*?(?=^def [a-z_][a-z0-9_]*\\b|\\z)", Regexp::MULTILINE)
    source[pattern]
  end

  # Whether one top-level method of a single-file script reaches another, by
  # following the names it calls. Shallow on purpose: it reads call spellings in
  # a body, so a dynamic send is invisible to it — postpro has none on this path,
  # and a reachability check that tried to be exact would be a second interpreter.
  def reaches?(source, from, target, seen = [])
    return false if seen.include?(from)

    body = method_body(source, from)
    return false unless body
    return true if body.include?(target)

    body.scan(/\b([a-z_][a-z0-9_]*)\(/).flatten.uniq
        .any? { |callee| reaches?(source, callee, target, seen + [from]) }
  end

  # The model string is not the invariant. This pinned flux-1.1-pro-ultra and
  # went red the day 495bb98d8 made FLUX 2 the default — a deliberate upgrade
  # the test read as a regression, which is what a version literal in an
  # assertion always ends up doing. What has to hold is that FINAL_MODEL names a
  # model replicate actually knows, and vocab-check is the check that proves it:
  # replicate.rb refuses a FINAL_MODEL with no MODEL_CAPABILITIES entry.
  def test_replicate_vocab_check_exits_zero_and_final_model_is_known
    out, status = run_script(REPLICATE, "vocab-check")
    assert status.success?, "replicate vocab-check failed:\n#{out}"

    source = File.read(REPLICATE)
    final = source[/^FINAL_MODEL = "([^"]+)"/, 1]
    assert final, "replicate must declare a FINAL_MODEL"
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
