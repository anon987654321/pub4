# frozen_string_literal: true

require_relative "test_helper"

class TestCheckpoint < Minitest::Test
  def test_create_and_restore_round_trip
    Dir.mktmpdir do |root|
      path = File.join(root, "lib", "sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "before\n")
      checkpoint = Master::Ground::Checkpoint.new(
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
      checkpoint = Master::Ground::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))

      assert_raises(ArgumentError) { checkpoint.create(label: "bad", files: ["../outside"]) }
    end
  end
end
