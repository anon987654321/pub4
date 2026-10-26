# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "test_helper"
require_relative "../lib/fix/transaction"

# A /fix run that crashes leaves the working tree as it found it. On 2026-10-23 two runs crashed at
# the start of their first pass and left 18 files each holding blank lines the observation's autofix
# had written: the writes sat outside every transaction, and the stages after the crash read them.
class TestFixCrashLeavesTree < Minitest::Test
  class FakeGit
    def changed_paths = []
    def head = "abc1234"
  end

  def setup = Master::Fix::AutofixGuard.reset!
  def teardown = Master::Fix::AutofixGuard.reset!

  def git(root, *args) = system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

  def committed_repo(root)
    git(root, "init", "-q")
    File.write(File.join(root, "a.rb"), "A = 1\n")
    git(root, "add", "a.rb")
    git(root, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
  end

  # A pass's own write is the pass's to roll back; another writer's edit to a tracked file is not.
  # The rollback refused both when the pass had never recorded its own write.
  def open_pass(root, paths)
    committer = Master::Fix::FixLoop::Committer.new(git: FakeGit.new, root:)
    committer.baseline!
    committer.begin_transaction!(Master::Fix::Transaction.new(root:, paths:))
    committer
  end

  def test_a_crashed_pass_rolls_back_its_own_write_and_leaves_another_writers
    Dir.mktmpdir do |root|
      ours, theirs = %w[a.rb b.rb].map { |name| File.join(root, name).tap { |path| File.write(path, "X = 1\n") } }
      committer = open_pass(root, %w[a.rb b.rb])
      File.write(ours, "X = 1\n\n")
      committer.attest_written!(ours)
      File.write(theirs, "X = 2\n")

      out, = capture_io { committer.abort_transaction! }

      assert_equal ["X = 1\n", "X = 2\n"], [File.read(ours), File.read(theirs)]
      assert_includes out, "b.rb"
    end
  end

# The process died with its pass open, and the journal only marked the run interrupted.
# The next run's sweep rolls the pass back; one whose file changed since is kept as a conflict.
def stranded_pass(root, content)
  path = File.join(root, "a.rb").tap { |file| File.write(file, "A = 1\n") }
  transaction = Master::Fix::Transaction.new(root:, paths: %w[a.rb])
  transaction.begin!
  File.write(path, content)
  transaction.observe!
  transaction.send(:release_lock)
  [path, transaction.id]
end

def sweep(root)
  loop = Master::Fix::FixLoop.allocate
  loop.instance_variable_set(:@transaction_root, root)
  capture_io { loop.send(:recover_stranded_transactions!) }.first
end

def test_the_next_run_rolls_back_a_pass_a_dead_process_left_open
  Dir.mktmpdir do |root|
    path, = stranded_pass(root, "A = 1\n\n")

    sweep(root)

    assert_equal "A = 1\n", File.read(path)
  end
end

def test_a_stranded_pass_whose_file_changed_since_is_kept_and_named
  Dir.mktmpdir do |root|
    path, id = stranded_pass(root, "A = 1\n\n")
    File.write(path, "A = 2\n")

    out = sweep(root)

    assert_equal "A = 2\n", File.read(path)
    assert_includes out, "stranded transaction #{id}"
  end
end

  # A rollback that leaves a file names it in dmesg, not only on the bus.
  def test_a_refused_rollback_is_reported_in_dmesg
    Dir.mktmpdir do |root|
      path = File.join(root, "a.rb").tap { |file| File.write(file, "A = 1\n") }
      committer = open_pass(root, %w[a.rb])
      File.write(path, "A = 2\n")

      out, = capture_io { committer.abort_transaction! }

      assert_match(/fix0: rollback left 1 file.*a\.rb/, out)
      assert_equal "A = 2\n", File.read(path)
    end
  end

  # The pipeline around a crashed repair: the observation's autofix wrote a file, the fix loop
  # crashed, and nothing after it may read or write the tree as though the repair had happened.
  class CrashedPass < Master::CLI::Pipeline::Pass
    attr_reader :proved

    def observations = (@observations ||= 0)

    # The first reading's autofix adds a blank line, as vertical_breath did.
    def run_observation(_arg, unit:, files: nil)
      @observations = observations + 1
      autofix(File.join(@root, "a.rb")) if unit == "obs0" && files.nil?
    end

    def autofix(path)
      before = File.read(path)
      File.write(path, "A = 1\n\n")
      Master::Fix::AutofixGuard.note_written(path, before:)
    end

    # The writing pass a /fix runs, on the posture a full scan takes.
    def repair(root)
      @apply = true
      fix_sections(resolved: root, shell: ".", posture: { scan_profile: "full" }, aesthetic: false, critique: false)
    end

    def proof_baseline(_abs) = nil
    def proof_section(*) = (@proved = true) && %w[proof ran]
    def repo_git = (@repo_git ||= Master::Io::GitOperations.new(@root))
    def repo_top = @root
    def run_fix(abs) = fix_verdict(@fix_loop.run(abs, requested: true), 0)
  end

  class CrashingLoop
    def run(*, **) = Master::Result.err("fix_loop: crash RuntimeError @ pass: refused", category: :crash)
    def last_terminal_state = :crash
  end

  # A repair that failed without crashing, judged by a proof that stays red, or held and delivered.
  class ProvedPass < CrashedPass
    def initialize(proof_holds:, **)
      super(**)
      @proof_holds = proof_holds
    end

    def proof_section(*)
      deliver if @proof_holds
      @proof_holds ? %w[proof held] : %w[proof red]
    end

    def deliver = system("git", "-C", @root, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "deliver")
  end

  class FailingLoop
    def run(*, **) = Master::Result.err("fix_loop: uninspectable inputs remain", category: :validation)
    def last_terminal_state = :validation_failed
  end

  # STUDIO's proof was red, nothing was delivered, and 19 files of the observation's autofix stayed.
  def test_a_red_proof_puts_back_the_observations_autofix
    Dir.mktmpdir do |root|
      committed_repo(root)
      pass = ProvedPass.new(scanner: nil, fix_loop: FailingLoop.new, root:, proof_holds: false)
      capture_io { pass.repair(root) }

      assert_equal "A = 1\n", File.read(File.join(root, "a.rb"))
    end
  end

  def test_a_held_proof_keeps_the_autofix_it_delivered
    Dir.mktmpdir do |root|
      committed_repo(root)
      pass = ProvedPass.new(scanner: nil, fix_loop: FailingLoop.new, root:, proof_holds: true)
      capture_io { pass.repair(root) }

      assert_equal "A = 1\n\n", File.read(File.join(root, "a.rb"))
    end
  end

  def test_a_crashed_repair_puts_back_the_observations_autofix_and_stops
    Dir.mktmpdir do |root|
      committed_repo(root)
      pass = CrashedPass.new(scanner: nil, fix_loop: CrashingLoop.new, root:)
      capture_io { pass.repair(root) }

      assert_equal "A = 1\n", File.read(File.join(root, "a.rb"))
      assert_equal 1, pass.observations, "no stage may re-read the tree after a crashed repair"
      refute pass.proved, "no proof, and so no delivery, after a crashed repair"
    end
  end
end
