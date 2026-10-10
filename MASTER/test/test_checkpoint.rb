# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestCheckpoint < Minitest::Test
  def test_create_and_restore_round_trip
    Dir.mktmpdir do |root|
      path = File.join(root, "lib", "sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "before\n")
      checkpoint = Master::Fix::Checkpoint.new(
        root:,
        dir: File.join(root, ".master", "checkpoints"),
      )
      manifest = checkpoint.create(label: "test", files: ["lib/sample.rb"])
      assert_equal 2, manifest[:format_version]
      assert_equal Digest::SHA256.hexdigest("before\n"), manifest.dig(:sha256, "lib/sample.rb")
      File.write(path, "after\n")

      checkpoint.restore(manifest[:id])
      assert_equal "before\n", File.read(path)
    end
  end

  def test_create_rejects_paths_outside_root
    Dir.mktmpdir do |root|
      checkpoint = Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))

      assert_raises(ArgumentError) { checkpoint.create(label: "bad", files: ["../outside"]) }
    end
  end

  def test_restore_refuses_tampered_checkpoint_before_overwriting_source
    Dir.mktmpdir do |root|
      path = File.join(root, "lib", "sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "before\n")
      checkpoint = Master::Fix::Checkpoint.new(
        root:,
        dir: File.join(root, ".master", "checkpoints"),
      )
      manifest = checkpoint.create(label: "integrity", files: ["lib/sample.rb"])
      checkpoint_path = File.join(checkpoint.dir, manifest.fetch(:id), "lib", "sample.rb")
      File.write(checkpoint_path, "tampered\n")
      File.write(path, "current\n")

      assert_raises(Master::Fix::Checkpoint::IntegrityError) do
        checkpoint.restore(manifest.fetch(:id))
      end
      assert_equal "current\n", File.read(path)
    end
  end

  def test_legacy_checkpoint_without_checksums_remains_restorable
    Dir.mktmpdir do |root|
      path = File.join(root, "lib", "sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "before\n")
      checkpoint = Master::Fix::Checkpoint.new(
        root:,
        dir: File.join(root, ".master", "checkpoints"),
      )
      manifest = checkpoint.create(label: "legacy", files: ["lib/sample.rb"])
      manifest_path = File.join(checkpoint.dir, manifest.fetch(:id), "manifest.json")
      legacy = JSON.parse(File.read(manifest_path))
      legacy.delete("format_version")
      legacy.delete("sha256")
      File.write(manifest_path, JSON.generate(legacy))
      File.write(path, "current\n")

      checkpoint.restore(manifest.fetch(:id))
      assert_equal "before\n", File.read(path)
    end
  end

end
