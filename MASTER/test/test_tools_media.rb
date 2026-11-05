# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require_relative "../../STUDIO/replicate/client"

# The MASTER/tools vocab-check is the real contract for postpro. It used to be
# operator memory. A table that fails quiet is how unread temp: and a costume
# --final model survive. Replicate's own vocab table retired with replicate.rb:
# STUDIO/replicate/client.rb reads the live provider schema instead of a stale
# local table, and models.yml owns the model vocabulary under its registry
# guards.
class TestToolsMedia < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  POSTPRO = File.join(ROOT, "STUDIO", "postpro", "postpro.rb")

  # postpro.rb loads its methods from lib/, so its source is the entry file and lib/ together.
  def postpro_source
    files = [POSTPRO] + Dir[File.join(File.dirname(POSTPRO), "lib", "*.rb")].sort
    files.map { |path| File.read(path) }.join("\n")
  end

  def test_studio_replicate_pagination_rejects_external_cursor_urls
    client = Studio::ReplicateClient.new(token: "studio-replicate-test")
    request = nil
    response = Struct.new(:code, :body).new(
      "200",
      JSON.generate("results" => [], "next" => "https://attacker.invalid/v1/models?cursor=secret"),
    )
    http = Object.new
    http.define_singleton_method(:request) { |value| request = value; response }

    Net::HTTP.stub(:start, ->(_host, _port, **_options, &block) { block.call(http) }) do
      error = assert_raises(ArgumentError) { client.models }
      assert_match(/outside the Replicate API origin/, error.message)
    end

    assert_equal "Token studio-replicate-test", request["Authorization"]
    assert_equal "/v1/models", request.path
  end

  def test_studio_replicate_pagination_rejects_a_repeated_cursor
    client = Studio::ReplicateClient.new(token: "studio-replicate-test")
    request_count = 0
    page = Struct.new(:code, :body).new(
      "200",
      JSON.generate("results" => [], "next" => "#{Studio::ReplicateClient::BASE}/models"),
    )
    http = Object.new
    http.define_singleton_method(:request) { |_value| request_count += 1; page }

    Net::HTTP.stub(:start, ->(_host, _port, **_options, &block) { block.call(http) }) do
      error = assert_raises(ArgumentError) { client.models }
      assert_match(/repeated a cursor/, error.message)
    end

    assert_equal 1, request_count
  end

  def test_studio_replicate_token_files_must_be_private_regular_user_files
    Dir.mktmpdir do |directory|
      path = File.join(directory, "env")
      File.write(path, "REPLICATE_API_TOKEN=secret\n")
      File.chmod(0o600, path)
      assert Studio::ReplicateClient.private_token_file?(path)

      File.chmod(0o640, path)
      refute Studio::ReplicateClient.private_token_file?(path)

      File.chmod(0o600, path)
      target = File.join(directory, "secret")
      File.rename(path, target)
      File.symlink(target, path)
      refute Studio::ReplicateClient.private_token_file?(path)
    end
  end

  def test_studio_replicate_api_requests_use_the_declared_tls_timeouts
    client = Studio::ReplicateClient.new(token: "studio-replicate-test")
    request = nil
    response = Struct.new(:code, :body).new("200", JSON.generate("username" => "studio"))
    http = Object.new
    http.define_singleton_method(:request) { |value| request = value; response }

    Net::HTTP.stub(:start, lambda { |host, port, **options, &block|
      assert_equal "api.replicate.com", host
      assert_equal 443, port
      assert_equal true, options.fetch(:use_ssl)
      assert_equal Studio::ReplicateClient::OPEN_TIMEOUT_SECONDS, options.fetch(:open_timeout)
      assert_equal Studio::ReplicateClient::READ_TIMEOUT_SECONDS, options.fetch(:read_timeout)
      block.call(http)
    }) do
      assert_equal "studio", client.account_username
    end

    assert_equal "Token studio-replicate-test", request["Authorization"]
  end

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
      "border_style" => %w[polaroid_frame],
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
