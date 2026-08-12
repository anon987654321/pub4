# frozen_string_literal: true

require "test_helper"
require "master"
require "tmpdir"

class WorldRollbackTest < Minitest::Test
  def test_rollback_preserves_untracked_files
    Dir.mktmpdir do |root|
      init_git!(root)
      File.write(File.join(root, "tracked.txt"), "before\n")
      system("git", "-C", root, "add", "tracked.txt", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "commit", "-qm", "seed", out: File::NULL, err: File::NULL)

      File.write(File.join(root, "tracked.txt"), "pre-effect\n")
      File.write(File.join(root, "untracked.txt"), "keep me\n")

      world = Master::Core::World.new(root:)
      checkpoint = world.checkpoint

      File.write(File.join(root, "tracked.txt"), "failed-effect\n")
      observation = world.rollback(checkpoint)

      assert observation.ok?, observation.message
      assert_equal "pre-effect\n", File.read(File.join(root, "tracked.txt"))
      assert_equal "keep me\n", File.read(File.join(root, "untracked.txt"))
    end
  end

  private

  def init_git!(root)
    system("git", "-C", root, "init", "-q")
    system("git", "-C", root, "config", "user.email", "rollback@test.local")
    system("git", "-C", root, "config", "user.name", "rollback test")
  end
end
