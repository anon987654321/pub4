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

  def stale_name(age:, pid: 123, suffix: nil)
    timestamp = (Time.now.to_f - age).to_i
    "gems.stale-#{pid}-#{timestamp}#{suffix ? "-#{suffix}" : ""}"
  end

  def store(name, mtime_age: nil)
    path = File.join(@store_key, name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "marker"), "retained until eligible")
    if mtime_age
      timestamp = Time.now - mtime_age
      File.utime(timestamp, timestamp, path)
    end
    path
  end

  def test_candidates_use_quarantine_age_not_original_directory_mtime
    old = store(stale_name(age: SWEEP::TTL_SECONDS + 60), mtime_age: 0)
    store(stale_name(age: SWEEP::TTL_SECONDS - 60, pid: 124), mtime_age: SWEEP::TTL_SECONDS + 3600)
    store("gems", mtime_age: SWEEP::TTL_SECONDS + 60)
    store("gems.stale-not-a-store", mtime_age: SWEEP::TTL_SECONDS + 60)

    assert_equal [old], SWEEP.candidates(@bundle_root).sort
  end

  def test_default_sweep_is_a_report_only_census
    old = store(stale_name(age: SWEEP::TTL_SECONDS + 60), mtime_age: 0)

    assert_equal 1, SWEEP.sweep(@bundle_root)
    assert File.directory?(old)
    assert_equal "retained until eligible", File.read(File.join(old, "marker"))
  end

  def test_apply_prunes_only_stores_whose_quarantine_ttl_expired
    old = store(stale_name(age: SWEEP::TTL_SECONDS + 60), mtime_age: 0)
    fresh = store(stale_name(age: SWEEP::TTL_SECONDS - 60, pid: 124), mtime_age: SWEEP::TTL_SECONDS + 3600)
    active = store("gems", mtime_age: SWEEP::TTL_SECONDS + 60)

    assert_equal 1, SWEEP.sweep(@bundle_root, apply: true)
    refute File.exist?(old)
    assert File.directory?(fresh)
    assert File.directory?(active)
  end

  def test_symlinked_stale_path_is_never_a_candidate
    old = store(stale_name(age: SWEEP::TTL_SECONDS + 60), mtime_age: 0)
    link = File.join(@store_key, stale_name(age: 60, pid: 124))
    File.symlink(old, link)

    refute_includes SWEEP.candidates(@bundle_root), link
    assert_equal "retained until eligible", File.read(File.join(old, "marker"))
  end

  def test_symlinked_store_key_is_not_traversed
    real_key = @store_key
    FileUtils.rm_rf(real_key)
    target = File.join(@root, "external-key")
    FileUtils.mkdir_p(target)
    stale = File.join(target, stale_name(age: SWEEP::TTL_SECONDS + 60))
    FileUtils.mkdir_p(stale)
    File.utime(Time.now, Time.now, stale)
    File.symlink(target, real_key)

    assert_empty SWEEP.candidates(@bundle_root)
  end
end
