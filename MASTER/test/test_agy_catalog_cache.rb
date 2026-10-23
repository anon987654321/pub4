# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "cli/routing/model_router"

# `agy models` took 1.5s of every boot. Its listing is kept for a day, keyed by the binary, and an upgraded
# binary is asked again.
class TestAgyCatalogCache < Minitest::Test
  # The pool's agy catalogue with its binary, cache file and probe pointed at a scratch directory.
  class AgyPool
    include Master::CLI::Routing::ModelRouter::Pool
    public :agy_catalog_models
    attr_reader :probes

    def initialize(dir, binary)
      @dir = dir
      @binary = binary
      @probes = 0
    end

    def agy_binary = @binary
    def agy_catalog_file = File.join(@dir, "agy_models.json")

    def run_probe(*)
      @probes += 1
      "gemini-3-pro    fast reasoning\nclaude-sonnet-5  balanced\n"
    end
  end

  def with_agy
    Dir.mktmpdir do |dir|
      binary = File.join(dir, "agy")
      File.write(binary, "#!/bin/sh\n")
      File.chmod(0o755, binary)
      yield dir, binary
    end
  end

  def test_a_second_process_reads_the_listing_instead_of_asking
    with_agy do |dir, binary|
      first = AgyPool.new(dir, binary)
      assert_equal %w[agy:gemini-3-pro agy:claude-sonnet-5], first.agy_catalog_models

      second = AgyPool.new(dir, binary)
      assert_equal first.agy_catalog_models, second.agy_catalog_models
      assert_equal [1, 0], [first.probes, second.probes]
    end
  end

  def test_an_upgraded_binary_is_asked_again
    with_agy do |dir, binary|
      AgyPool.new(dir, binary).agy_catalog_models
      later = File.mtime(binary) + 60
      File.utime(later, later, binary)

      upgraded = AgyPool.new(dir, binary)
      upgraded.agy_catalog_models
      assert_equal 1, upgraded.probes
    end
  end
end
