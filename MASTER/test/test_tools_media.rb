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

  # postpro.rb loads its methods from lib/, so its source is the entry file and lib/ together.
  def postpro_source
    files = [POSTPRO] + Dir[File.join(File.dirname(POSTPRO), "lib", "*.rb")].sort
    files.map { |path| File.read(path) }.join("\n")
  end
  REPLICATE = File.join(ROOT, "MASTER/tools", "replicate", "replicate.rb")

  def test_postpro_key_readers_cover_every_declared_preset_knob
    source = postpro_source
    expected = {
      "stops" => %w[push_pull],
      "age" => %w[faded_print dye_fade expired_film],
      "print_stock" => %w[print_film],
      "exposure_secs" => %w[reciprocity_failure],
      "k1" => %w[lens_distortion],
      "f_number" => %w[diffraction_blur],
      "tonemap_ev" => %w[tonemap],
      "temp" => %w[spectral_temp color_temp],
      "lens" => %w[vintage_lens],
      "tonemap" => %w[tonemap],
      "azimuth" => %w[relight],
      "shape" => %w[relight],
      "aspect_ratio" => %w[cinemascope_bars],
      "border_style" => %w[polaroid_frame]
    }

    reader_source = source[/key_readers = \{(.*?)^  \}/m, 1]
    assert reader_source, "postpro must define its preset key-reader contract"
    actual = reader_source.scan(/([a-z_][a-z0-9_]*):\s*%w\[([^\]]+)\]/)
                          .to_h { |key, readers| [key, readers.split] }
    assert_equal expected, actual, "every operator-set preset knob needs one declared reader"

    presets = source.scan(/^  ([a-z0-9_]+): \{ fx: %w\[([^\]]+)\]([^}]*)\}/m)
    assert_operator presets.size, :>, 0, "preset scanner must reach the source table"
    # Some supported knobs are runtime-capable but no current preset sets
    # them. Check every declaration that exists; do not require unused knobs to
    # appear in the preset table merely to make the fixture non-empty.
    expected.each do |key, readers|
      matching = presets.select { |_, _, rest| rest.match?(/\b#{Regexp.escape(key)}:/) }
      matching.each do |name, fx, _rest|
        assert(fx.split.intersect?(readers),
               "#{name} declares #{key}: but its chain has no #{readers.join('/')} reader")
      end
    end
  end

  def test_postpro_rejects_unknown_presets_instead_of_silently_returning_the_input
    source = postpro_source
    body = method_body(source, "preset")

    assert body, "preset resolver must exist"
    assert_match(/raise ArgumentError, "unknown preset/, body)
    refute_match(/return image unless p/, body)
  end

  def test_method_body_reader_covers_nested_blocks_without_absorbing_neighbours
    source = postpro_source
    methods = method_bodies(source)
    random = methods.fetch("run_random")
    watch = methods.fetch("run_watch")

    assert_includes random, "process_file("
    assert_includes watch, "grade_watched("
    refute_includes random, "def run_uplift"
    refute_includes watch, "RANDOM_CHAIN_LENGTH ="
  end

  def test_reachability_ignores_comment_and_string_mentions
    source = <<~RUBY
      def render
        # apply_finishing_grain(image, :house)
        label = "apply_finishing_grain(image, :house)"
        image.call(:apply_finishing_grain)
      end
    RUBY

    refute reaches?(source, "render", "apply_finishing_grain")
  end

  def test_postpro_finishing_grain_uses_the_preset_stock
    source = postpro_source
    methods = method_bodies(source)
    assert_includes source, "def apply_finishing_grain"
    assert_includes source, "GRAIN_REFERENCE_WIDTH"
    refute_match(/grain\(processed, 400, :kodak_portra, 0\.35\)/, source)
    # Reachability, not one particular spelling, is the invariant.
    %w[process_file run_random run_uplift run_one_shot run_watch].each do |name|
      assert methods.key?(name), "#{name} must still exist"
      assert reaches?(source, name, "apply_finishing_grain", methods:),
             "#{name} must reach apply_finishing_grain, through however many helpers it calls"
    end
  end

  # Prism supplies exact source spans, so nested blocks cannot truncate a
  # method and comments/constants beside it cannot be mistaken for its body.
  def method_bodies(source)
    require "prism"
    parsed = Prism.parse(source)
    raise ArgumentError, "Postpro source failed to parse" unless parsed.success?

    parsed.value.statements.body.each_with_object({}) do |node, methods|
      next unless node.is_a?(Prism::DefNode)

      methods[node.name.to_s] = source.byteslice(node.location.start_offset...node.location.end_offset)
    end
  end

  def method_body(source, name)
    method_bodies(source)[name.to_s]
  end

  # Calls are read from Prism nodes, not regexes over source text: comments and
  # string literals must not be able to satisfy a reachability contract.
  def method_calls(body)
    parsed = Prism.parse(body)
    raise ArgumentError, "method source failed to parse" unless parsed.success?

    definition = parsed.value.statements.body.first
    return [] unless definition.is_a?(Prism::DefNode)

    names = []
    pending = [definition.body].compact
    until pending.empty?
      node = pending.pop
      next if node.is_a?(Prism::DefNode)
      names << node.name.to_s if node.is_a?(Prism::CallNode) && node.receiver.nil?
      pending.concat(node.child_nodes.compact)
    end
    names.uniq
  end

  # Follow unqualified calls between top-level methods. Cache the source spans
  # and each method's call set once, so recursion is deterministic and ignores
  # comments, strings, and calls on unrelated explicit receivers.
  def reaches?(source, from, target, seen = [], methods: nil, calls: nil)
    return false if seen.include?(from)

    methods ||= method_bodies(source)
    calls ||= methods.transform_values { |body| method_calls(body) }
    method = from.to_s
    return false unless methods.key?(method)
    return true if calls.fetch(method, []).include?(target.to_s)

    calls.fetch(method, []).any? do |callee|
      methods.key?(callee) &&
        reaches?(source, callee, target, seen + [method], methods:, calls:)
    end
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
