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
      # The effect that failed is what rollback undoes. Without it there is no
      # scope, and the only thing left to do would be a tree-wide reset.
      effect = Master::Core::Effect.write("tracked.txt", "failed-effect\n")
      observation = world.rollback(checkpoint, effect)

      assert observation.ok?, observation.message
      assert_equal "pre-effect\n", File.read(File.join(root, "tracked.txt"))
      assert_equal "keep me\n", File.read(File.join(root, "untracked.txt"))
    end
  end

  # The reason the scope exists. `git reset --hard HEAD` undid the failed write by
  # discarding every uncommitted change in the tree — and this checkout is shared,
  # so "every uncommitted change" includes whatever another session was midway
  # through. Undoing one write must not cost someone else their work.
  def test_rollback_leaves_a_concurrent_change_to_another_file_alone
    Dir.mktmpdir do |root|
      init_git!(root)
      File.write(File.join(root, "mine.txt"), "before\n")
      File.write(File.join(root, "theirs.txt"), "before\n")
      system("git", "-C", root, "add", ".", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "commit", "-qm", "seed", out: File::NULL, err: File::NULL)

      world = Master::Core::World.new(root:)
      checkpoint = world.checkpoint

      File.write(File.join(root, "mine.txt"), "failed-effect\n")
      # Another session, editing a different file in the same tree, after the
      # checkpoint was taken — so this change is in no patch anywhere.
      File.write(File.join(root, "theirs.txt"), "their work in progress\n")

      observation = world.rollback(checkpoint, Master::Core::Effect.write("mine.txt", "failed-effect\n"))

      assert observation.ok?, observation.message
      assert_equal "before\n", File.read(File.join(root, "mine.txt")), "the failed write was not undone"
      assert_equal "their work in progress\n", File.read(File.join(root, "theirs.txt")),
                   "rollback destroyed another session's concurrent change"
    end
  end

  # An exec can touch anything, so there is no scope to undo it within. Saying so
  # is the honest answer; resetting the tree on the guess is not.
  def test_rollback_refuses_rather_than_resetting_when_it_cannot_scope
    Dir.mktmpdir do |root|
      init_git!(root)
      File.write(File.join(root, "tracked.txt"), "before\n")
      system("git", "-C", root, "add", ".", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "commit", "-qm", "seed", out: File::NULL, err: File::NULL)
      File.write(File.join(root, "tracked.txt"), "dirty\n")

      world = Master::Core::World.new(root:)
      checkpoint = world.checkpoint
      File.write(File.join(root, "tracked.txt"), "dirtier\n")

      observation = world.rollback(checkpoint, Master::Core::Effect.exec(["true"]))

      refute observation.ok?, "an unscopable rollback must report, not silently succeed"
      assert_match(/no path to scope to/, observation.message)
      assert_equal "dirtier\n", File.read(File.join(root, "tracked.txt")),
                   "refusing to scope must also mean refusing to reset"
    end
  end

  private

  def init_git!(root)
    system("git", "-C", root, "init", "-q")
    system("git", "-C", root, "config", "user.email", "rollback@test.local")
    system("git", "-C", root, "config", "user.name", "rollback test")
  end
end
