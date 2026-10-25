# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require_relative "../lib/boot/stale_bundle_sweep"

class TestStaleBundleSweep < Minitest::Test
  SWEEP = Master::Boot::StaleBundleSweep

  def setup
    @root = Dir.mktmpdir("master-stale-bundles-")
    @bundle_root = File.join(@root, ".master", "bundler")
    @store_key = File.join(@bundle_root, "0123456789abcdef")
    FileUtils.mkdir_p(@store_key)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def store(name, age:)
    path = File.join(@store_key, name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "marker"), "retained until eligible")
    timestamp = Time.now - age
    File.utime(timestamp, timestamp, path)
    path
  end

  def test_candidates_include_only_old_stale_store_directories
    old = store("gems.stale-123-456", age: SWEEP::TTL_SECONDS + 60)
    store("gems.stale-123-789", age: SWEEP::TTL_SECONDS - 60)
    store("gems", age: SWEEP::TTL_SECONDS + 60)
    store("gems.stale-not-a-store", age: SWEEP::TTL_SECONDS + 60)

    assert_equal [old], SWEEP.candidates(@bundle_root).sort
  end

  def test_default_sweep_is_a_report_only_census
    old = store("gems.stale-123-456", age: SWEEP::TTL_SECONDS + 60)

    assert_equal 1, SWEEP.sweep(@bundle_root)
    assert File.directory?(old)
    assert_equal "retained until eligible", File.read(File.join(old, "marker"))
  end

  def test_apply_prunes_only_expired_stale_stores
    old = store("gems.stale-123-456", age: SWEEP::TTL_SECONDS + 60)
    fresh = store("gems.stale-123-789", age: SWEEP::TTL_SECONDS - 60)
    active = store("gems", age: SWEEP::TTL_SECONDS + 60)

    assert_equal 1, SWEEP.sweep(@bundle_root, apply: true)
    refute File.exist?(old)
    assert File.directory?(fresh)
    assert File.directory?(active)
  end

  def test_symlinked_stale_path_is_never_a_candidate
    old = store("gems.stale-123-456", age: SWEEP::TTL_SECONDS + 60)
    link = File.join(@store_key, "gems.stale-124-789")
    File.symlink(old, link)

    refute_includes SWEEP.candidates(@bundle_root), link
    assert_equal "retained until eligible", File.read(File.join(old, "marker"))
  end

  def test_symlinked_store_key_is_not_traversed
    real_key = @store_key
    FileUtils.rm_rf(real_key)
    target = File.join(@root, "external-key")
    FileUtils.mkdir_p(target)
    stale = File.join(target, "gems.stale-123-456")
    FileUtils.mkdir_p(stale)
    File.utime(Time.now - SWEEP::TTL_SECONDS - 60, Time.now - SWEEP::TTL_SECONDS - 60, stale)
    File.symlink(target, real_key)

    assert_empty SWEEP.candidates(@bundle_root)
  end
end
