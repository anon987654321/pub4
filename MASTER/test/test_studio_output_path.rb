# frozen_string_literal: true

require "minitest/autorun"
require_relative "../contracts/studio"

# Each STUDIO output-path query boots dilla.rb. One media dispatch asked for
# reference_root several times, which ran a single test past its 30s bound.
class TestStudioOutputPath < Minitest::Test
  Status = Struct.new(:ok) do
    def success? = ok
    def exitstatus = 0
  end

  def setup
    @calls = []
    calls = @calls

    @original = Contracts::Studio.method(:run_bounded)
    Contracts::Studio.define_singleton_method(:run_bounded) do |argv, chdir:, timeout:|
      calls << argv
      ["/srv/studio/#{argv[3]}/#{calls.size}\n", Status.new(true)]
    end
    @dilla = Contracts::Studio.method(:dilla_script)
    Contracts::Studio.define_singleton_method(:dilla_script) { "/srv/studio/dilla.rb" }
    Contracts::Studio.output_path_cache.clear
  end

  def teardown
    Contracts::Studio.define_singleton_method(:run_bounded, @original)
    Contracts::Studio.define_singleton_method(:dilla_script, @dilla)
    Contracts::Studio.output_path_cache.clear
  end

  def test_reference_root_is_asked_once_per_environment
    first = Contracts::Studio.output_path(kind: :reference_root)
    assert_equal first, Contracts::Studio.output_path(kind: :reference_root)
    assert_equal 1, @calls.size

    ENV["STUDIO_OUTPUT_PATH_PROBE"] = "changed"
    refute_equal first, Contracts::Studio.output_path(kind: :reference_root)
    assert_equal 2, @calls.size
  ensure
    ENV.delete("STUDIO_OUTPUT_PATH_PROBE")
  end

  def test_the_clock_dependent_render_directory_is_never_cached
    at = Time.utc(2026, 11, 5)
    Contracts::Studio.output_path(kind: :dilla_render_directory, at:)
    Contracts::Studio.output_path(kind: :dilla_render_directory, at:)
    assert_equal 2, @calls.size
    assert_equal at.iso8601, @calls.last.last
  end
end
