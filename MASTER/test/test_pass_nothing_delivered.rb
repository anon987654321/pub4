# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "test_helper"

# A run that committed nothing and whose autofix left nothing has nothing to prove: the
# baseline stands, and the suites are not run again to say so.
class TestPassNothingDelivered < Minitest::Test
  # Exposes the delivery check.
  class Pass < Master::CLI::Pipeline::Pass
    def delivered_nothing_since?(head) = nothing_delivered?(head)

    def failed_repair_since(head, changes)
      @repair_before = head
      fail_stage("fix", "transaction recovery found a concurrent edit")
      repair_unproven(changes)
    end
  end

  def setup = Master::Fix::AutofixGuard.reset!
  def teardown = Master::Fix::AutofixGuard.reset!

  def git(root, *args) = system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

  def committed_repo(root)
    git(root, "init", "-q")
    File.write(File.join(root, "a.rb"), "A = 1\n")
    git(root, "add", "a.rb")
    git(root, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
    Open3.capture2("git", "-C", root, "rev-parse", "HEAD").first.strip
  end

  def test_no_commit_and_no_autofix_write_is_nothing_delivered
    Dir.mktmpdir do |root|
      head = committed_repo(root)
      File.write(File.join(root, "theirs.rb"), "B = 1\n")

      assert Pass.new(scanner: nil, fix_loop: nil, root:).delivered_nothing_since?(head)
    end
  end

  def test_an_autofix_write_still_standing_is_something_to_prove
    Dir.mktmpdir do |root|
      head = committed_repo(root)
      File.write(File.join(root, "a.rb"), "A = 2\n")
      Master::Fix::AutofixGuard.note_written(File.join(root, "a.rb"))

      refute Pass.new(scanner: nil, fix_loop: nil, root:).delivered_nothing_since?(head)
    end
  end

  # Another writer's edit fills the diff, but the failed repair delivered
  # nothing: the tree-wide re-observe after it would only re-read obs0's tree.
  def test_a_failed_repair_that_delivered_nothing_skips_the_reread
    Dir.mktmpdir do |root|
      head = committed_repo(root)
      File.write(File.join(root, "theirs.rb"), "B = 1\n")
      pass = Pass.new(scanner: nil, fix_loop: nil, root:)

      assert_equal Pass::REPAIR_UNPROVEN, pass.failed_repair_since(head, "uncommitted, in the working tree")
    end
  end
end
