# frozen_string_literal: true

require_relative "test_helper"

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

  def test_create_rejects_paths_that_traverse_a_symlink
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "secret.rb"), "outside\n")
        File.symlink(outside, File.join(root, "linked"))
        checkpoint = Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))

        assert_raises(ArgumentError) do
          checkpoint.create(label: "bad", files: ["linked/secret.rb"])
        end
      end
    end
  end

  def test_restore_refuses_when_a_destination_parent_becomes_a_symlink
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |outside|
        path = File.join(root, "lib", "sample.rb")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "inside before\n")
        checkpoint = Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))
        manifest = checkpoint.create(label: "test", files: ["lib/sample.rb"])

        FileUtils.rm_rf(File.join(root, "lib"))
        File.symlink(outside, File.join(root, "lib"))
        outside_path = File.join(outside, "sample.rb")
        File.write(outside_path, "do not overwrite\n")

        assert_raises(ArgumentError) { checkpoint.restore(manifest[:id]) }
        assert_equal "do not overwrite\n", File.read(outside_path)
      end
    end
  end

  def test_restore_rejects_a_symlinked_checkpoint_directory
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |outside|
        checkpoint = Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))
        manifest = checkpoint.create(label: "test", files: [])
        stored = File.join(checkpoint.dir, manifest[:id])
        external = File.join(outside, manifest[:id])
        FileUtils.mv(stored, external)
        File.symlink(external, stored)

        assert_raises(ArgumentError) { checkpoint.restore(manifest[:id]) }
      end
    end
  end
end
