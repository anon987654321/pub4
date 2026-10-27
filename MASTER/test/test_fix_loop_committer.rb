# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

# The fix-loop committer commits only what its own pass changed: never a path
# that was already dirty when the pass began, never the shared index, and never
# a tree where an autofix left Ruby unparseable.
class TestFixLoopCommitter < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  # changed_paths answers the baseline first, then the tree after the pass.
  class FakeGit
    attr_reader :commits, :pushes
    attr_writer :ahead

    def initialize(before, after)
      @answers = [before, after]
      @commits = []
      @pushes = 0
      @ahead = 0
    end

    def push = @pushes += 1
    def log_between(*) = ["abc1234 fix: ok"]
    def ahead_behind = [@ahead, 3]

    def changed_paths
      @answers.size > 1 ? @answers.shift : @answers.first
    end

    def commit(message, paths:)
      @commits << [message, paths]
    end

    def head = "abc1234"
  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def write_file(rel, src)
    path = File.join(@dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, src)
  end

  def run_committer(git, bus, message, baseline: true)
    committer = Master::Fix::FixLoop::Committer.new(git:, bus:, root: @dir)
    committer.baseline! if baseline
    committer.commit_if_dirty(message)
  end

  def blocked?(bus)
    bus.events.any? { |event, _payload| event == "fix_loop:commit_blocked" }
  end

  def test_commits_when_changed_ruby_parses
    write_file("lib/ok.rb", "FOO = {\n  a: 1,\n}.freeze\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: ok")
    assert_equal [["fix: ok", ["lib/ok.rb"]]], git.commits
    commit_event = bus.events.find { |event, _| event == "ops:commit" }
    assert_equal ["lib/ok.rb"], commit_event.last[:paths]
    assert_equal [], commit_event.last[:findings]
    refute blocked?(bus)
  end

  def test_blocks_commit_on_freeze_corruption
    write_file("lib/bad.rb", "FOO = {.freeze\n  a: 1,\n}.freeze\n")
    git = FakeGit.new([], ["lib/bad.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: bad")
    assert_empty git.commits
    assert blocked?(bus)
  end

  def test_blocks_commit_on_missing_end
    write_file("lib/bad2.rb", "def m\n  if x\n  end\n")
    git = FakeGit.new([], ["lib/bad2.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: bad2")
    assert_empty git.commits
    assert blocked?(bus)
  end

  # A fix that passed every check and was still not committed has to say why in the log, not only
  # on the bus.
  def test_a_blocked_commit_says_why_in_the_log
    write_file("lib/bad2.rb", "def x\n  1\n")
    git = FakeGit.new([], ["lib/bad2.rb"])
    bus = FakeBus.new

    out, = capture_io { run_committer(git, bus, "fix: bad") }

    assert blocked?(bus)
    assert_includes out, "deliver0: commit blocked, syntax, files lib/bad2.rb"
  end

  def test_ignores_non_ruby_changes
    write_file("README.md", "# hi\n")
    git = FakeGit.new([], ["README.md"])
    bus = FakeBus.new
    run_committer(git, bus, "docs: update")
    assert_equal [["docs: update", ["README.md"]]], git.commits
    refute blocked?(bus)
  end

  def test_a_path_dirty_before_the_pass_stays_out_of_the_commit
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/theirs.rb"], ["lib/theirs.rb", "lib/ok.rb"])
    run_committer(git, FakeBus.new, "fix: ok")
    assert_equal [["fix: ok", ["lib/ok.rb"]]], git.commits
  end

  # Another session's unparseable half-edit must neither be committed nor block
  # the pass's own commit.
  def test_foreign_broken_ruby_does_not_block_the_pass
    write_file("lib/theirs.rb", "def m\n")
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/theirs.rb"], ["lib/theirs.rb", "lib/ok.rb"])
    bus = FakeBus.new
    run_committer(git, bus, "fix: ok")
    assert_equal [["fix: ok", ["lib/ok.rb"]]], git.commits
    refute blocked?(bus)
  end

  def test_the_body_names_the_findings_in_committed_files
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/theirs.rb"], ["lib/theirs.rb", "lib/ok.rb"])
    findings = [
      { law: "NO_PUTS", file: "lib/ok.rb", line: 3 },
      { law: "LONG_LINE", file: File.join(@dir, "lib/ok.rb"), line: 9 },
      { law: "NO_PUTS", file: "lib/theirs.rb", line: 1 },
    ]
    committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)
    committer.baseline!
    committer.commit_if_dirty("fix_loop: llm-fix [pass 1]", findings:)

    assert_equal "fix_loop: llm-fix [pass 1]\n\nNO_PUTS lib/ok.rb:3\nLONG_LINE lib/ok.rb:9", git.commits.first.first
  end

  def test_architecture_scope_blocks_an_unowned_path
    git = FakeGit.new([], ["RAILS/apps.yml", "TODO.md"])
    bus = FakeBus.new
    committer = Master::Fix::FixLoop::Committer.new(git:, bus:, root: Master::REPO_ROOT)
    committer.baseline!(scope: ["rails"])
    committer.commit_if_dirty("fix: rails", owned_paths: [
      File.join(Master::REPO_ROOT, "RAILS/apps.yml"),
      File.join(Master::REPO_ROOT, "TODO.md"),
    ])

    assert_empty git.commits
    assert_equal 0, git.pushes
    event = bus.events.find { |name, _| name == "fix_loop:commit_blocked" }
    assert_equal "architecture_scope", event.last[:reason]
    assert_equal ["unowned"], event.last[:boundaries]
  end

  def test_architecture_scope_blocks_a_cross_boundary_commit
    git = FakeGit.new([], ["RAILS/apps.yml", "MASTER/README.md"])
    bus = FakeBus.new
    committer = Master::Fix::FixLoop::Committer.new(git:, bus:, root: Master::REPO_ROOT)
    committer.baseline!(scope: ["rails"])
    committer.commit_if_dirty(
      "fix: rails",
      owned_paths: [File.join(Master::REPO_ROOT, "RAILS/apps.yml"),
                    File.join(Master::REPO_ROOT, "MASTER/README.md")],
    )

    assert_empty git.commits
    assert_equal 0, git.pushes
    event = bus.events.find { |name, _| name == "fix_loop:commit_blocked" }
    assert_equal "architecture_scope", event.last[:reason]
    assert_equal ["master"], event.last[:boundaries]
  end

  # A target file already dirty when the pass began holds someone else's
  # uncommitted work; the fix must not ride into a commit with it.
  def test_owned_paths_exclude_files_dirty_at_baseline
    write_file("lib/ok.rb", "OK = 1\n")
    write_file("lib/fresh.rb", "FRESH = 1\n")
    git = FakeGit.new(["lib/ok.rb"], ["lib/ok.rb", "lib/fresh.rb"])
    bus = FakeBus.new
    committer = Master::Fix::FixLoop::Committer.new(git:, bus:, root: @dir)
    committer.baseline!
    committer.commit_if_dirty("fix: ok", owned_paths: [File.join(@dir, "lib/ok.rb"), File.join(@dir, "lib/fresh.rb")])

    assert_equal [["fix: ok", ["lib/fresh.rb"]]], git.commits
    assert committer.dirty_at_baseline?(File.join(@dir, "lib/ok.rb"))
    refute committer.dirty_at_baseline?("lib/fresh.rb")
    excluded = bus.events.find { |name, _| name == "fix_loop:baseline_dirty_excluded" }
    assert_equal ["lib/ok.rb"], excluded.last[:paths]
  end

  # Behind is the remote moving on; only a commit still ahead means the push
  # missed, and a delivery that missed stops the loop.
  def test_a_push_that_left_the_commit_behind_raises
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    git.ahead = 1
    bus = FakeBus.new

    with_push_env("each") do
      assert_raises(RuntimeError) { run_committer(git, bus, "fix: ok") }
    end
    assert_equal 1, git.pushes
    assert(bus.events.any? { |event, _| event == "fix_loop:commit_error" })
    refute(bus.events.any? { |event, _| event == "ops:commit" })
  end

# The freshness check wants a recorded read of what is on disk; only the ReadFile tool made
# one, so a repair the run wrote itself was blocked as stale. Attesting its own verified write
# clears it, and a file changed afterwards is stale again.
def test_a_repair_the_run_wrote_itself_commits_once_attested_and_not_after_a_later_edit
  write_file("lib/ok.rb", "OK = 1\n")
  git = FakeGit.new([], ["lib/ok.rb"])
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir, ground_truth: Master::Ground::Truth.new)
  committer.baseline!

  out, = capture_io { committer.commit_if_dirty("fix: ok") }
  assert_empty git.commits
  assert_includes out, "/fix did not write: lib/ok.rb"

  committer.attest_written!(File.join(@dir, "lib/ok.rb"))
  committer.commit_if_dirty("fix: ok")
  assert_equal 1, git.commits.size

  write_file("lib/ok.rb", "OK = 2\n")
  out, = capture_io { committer.commit_if_dirty("fix: again") }
  assert_equal 1, git.commits.size
  assert_includes out, "/fix did not write: lib/ok.rb"
end

# Another writer saving a corpus file mid-pass must not ride along in /fix's commit.
def test_a_file_fix_did_not_write_stays_out_of_its_commit
  write_file("lib/ok.rb", "OK = 1\n")
  write_file("app/page.html.erb", "<p>theirs</p>\n")
  git = FakeGit.new([], ["lib/ok.rb", "app/page.html.erb"])
  truth = Master::Ground::Truth.new
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir, ground_truth: truth)
  committer.baseline!
  committer.attest_written!(File.join(@dir, "lib/ok.rb"))

  capture_io { committer.commit_if_dirty("fix: ok") }
  committed = git.commits.flat_map(&:last)

  assert_equal ["lib/ok.rb"], committed
end

# The end of a pass delivers what the pass wrote, as its checkpoints do. A file the review's
# observation autofixed before the pass began has no recorded write; finish_transaction took it
# anyway, the freshness check refused it, and /fix MASTER ended DELIVERY_FAILED with its own
# verified repair undelivered.
def test_the_end_of_a_pass_delivers_only_what_the_pass_wrote
  paths = %w[lib/ok.rb lib/observed.rb]
  write_file("lib/ok.rb", "OK = 1\n")
  write_file("lib/observed.rb", "SEEN = 1\n")

  git = FakeGit.new([], paths)
  truth = Master::Ground::Truth.new

  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir, ground_truth: truth)
  committer.baseline!
  committer.begin_transaction!(Master::Fix::Transaction.new(root: @dir, paths:))
  committer.attest_written!(File.join(@dir, "lib/ok.rb"))

  out, = capture_io { committer.finish_transaction("fix: ok", owned_paths: paths) }

  assert_equal ["lib/ok.rb"], git.commits.flat_map(&:last)
  assert_includes out, "/fix did not write: lib/observed.rb"
end

# A rollback refused over another writer's edit ends the pass's transaction. The committer
# kept it, and every later fix in the pass failed "transaction not active" uncommitted.
def test_a_fix_after_the_transaction_ended_still_commits
  write_file("lib/ok.rb", "OK = 1\n")
  git = FakeGit.new([], ["lib/ok.rb"])
  committer = ended_transaction_committer(git)

  out, = capture_io { committer.commit_if_dirty("fix: ok") }

  assert_equal ["lib/ok.rb"], git.commits.flat_map(&:last)
  assert_includes out, "transaction ended mid-pass"
end

def ended_transaction_committer(git)
  truth = Master::Ground::Truth.new
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir, ground_truth: truth)
  committer.baseline!
  transaction = Master::Fix::Transaction.new(root: @dir, paths: ["lib/ok.rb"])
  committer.begin_transaction!(transaction)

  transaction.finalize!
  committer.attest_written!(File.join(@dir, "lib/ok.rb"))
  committer
end

# The hook refuses what bin/operator lint --changed-lines finds; /fix asks the same question before it stages,
# so a RuboCop correction that lengthened a 141-character line is rolled back instead of refused at commit.
def test_a_change_the_hook_would_refuse_is_named_before_staging
  refused = Struct.new(:success?).new(false)
  finding = "lint0: MASTER/lib/a.rb:85, line 141 chars (max 120)\n"

  found = Master::Io::Exec.stub(:capture3, [finding, "", refused]) do
    Master::Fix::FixLoop::HouseLint.findings(["lib/a.rb"], root: Master::ROOT)
  end

  assert_equal ["lint0: MASTER/lib/a.rb:85, line 141 chars (max 120)"], found
end

# The autofix's trailing comma on a 141-character line ended every MASTER pass at its first
# delivery. A file only the autofix wrote goes back and the pass's own repair still lands.
def test_an_autofix_write_the_house_lint_refuses_goes_back_and_the_repair_delivers
  wide = autofixed_wide_file
  git = FakeGit.new([], %w[lib/ok.rb lib/wide.rb])
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)
  committer.baseline!

  answers = [["lint0: lib/wide.rb:1, line 141 chars (max 120)"], []]
  lint = ->(*) { answers.shift || [] }
  capture_io { Master::Fix::FixLoop::HouseLint.stub(:findings, lint) { committer.commit_if_dirty("fix: ok") } }

  assert_equal ["lib/ok.rb"], git.commits.flat_map(&:last)
  assert_equal "WIDE = 1\n", File.read(wide)
ensure
  Master::Fix::AutofixGuard.reset!
end

def autofixed_wide_file
  write_file("lib/ok.rb", "OK = 1\n")
  Master::Fix::AutofixGuard.reset!
  wide = File.join(@dir, "lib/wide.rb")
  write_file("lib/wide.rb", "WIDE = [1,].freeze\n")
  Master::Fix::AutofixGuard.note_written(wide, before: "WIDE = 1\n")
  wide
end

def test_a_lint_that_fails_without_naming_a_line_still_blocks
  refused = Struct.new(:success?).new(false)

  found = Master::Io::Exec.stub(:capture3, ["boom\n", "", refused]) do
    Master::Fix::FixLoop::HouseLint.findings(["lib/a.rb"], root: Master::ROOT)
  end

  assert_equal ["bin/operator lint failed"], found
end

def test_the_house_lint_leaves_files_outside_the_repository_to_rubocop
  Master::Io::Exec.stub(:capture3, ->(*) { flunk "a temp tree is no commit's" }) do
    assert_empty Master::Fix::FixLoop::HouseLint.findings(["lib/ok.rb"], root: @dir)
  end
end

# A repair that took longer than the freshness window still commits its own unchanged write.
def test_a_slow_repairs_own_write_still_commits
  write_file("lib/ok.rb", "OK = 1\n")
  git = FakeGit.new([], ["lib/ok.rb"])
  truth = Master::Ground::Truth.new(max_age_seconds: -1)
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir, ground_truth: truth)
  committer.baseline!
  committer.attest_written!(File.join(@dir, "lib/ok.rb"))

  capture_io { committer.commit_if_dirty("fix: ok") }

  assert_equal 1, git.commits.size
end

# fix-here --no-publish: the commits stay local and the operator pushes.
def test_no_publish_holds_the_commits_instead_of_pushing
  write_file("lib/ok.rb", "OK = 1\n")
  git = FakeGit.new([], ["lib/ok.rb"])
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)
  committer.baseline!
  previous = ENV["MASTER_FIX_NO_PUBLISH"]
  ENV["MASTER_FIX_NO_PUBLISH"] = "1"
  begin
    with_push_env(nil) { committer.commit_if_dirty("fix: ok") }
    git.ahead = 1
    out, = capture_io { assert_equal :held, committer.publish_pending! }
  ensure
    previous ? ENV["MASTER_FIX_NO_PUBLISH"] = previous : ENV.delete("MASTER_FIX_NO_PUBLISH")
  end

  assert_equal 0, git.pushes
  assert_includes out, "deliver0: held, 1 commit(s) left local"
end

# Deferring publication is explicit; the default pushes every validated checkpoint.
def test_each_validated_checkpoint_pushes_by_default
  write_file("lib/ok.rb", "OK = 1\n")
  git = FakeGit.new([], ["lib/ok.rb"])
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)
  committer.baseline!

  with_push_env(nil) { committer.commit_if_dirty("fix: ok") }

  assert_equal 1, git.commits.size
  assert_equal 1, git.pushes
end

def test_end_mode_defers_publication_until_the_run_publishes
  write_file("lib/ok.rb", "OK = 1\n")
  git = FakeGit.new([], ["lib/ok.rb"])
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)
  committer.baseline!
  with_push_env("end") { committer.commit_if_dirty("fix: ok") }

  assert_equal 1, git.commits.size
  assert_equal 0, git.pushes

  git.ahead = 1
  # Unpushed work remains after publish_pending! only if the push missed.
  git.define_singleton_method(:push) { @pushes += 1; @ahead = 0 }
  with_push_env("end") { assert_equal :published, committer.publish_pending! }
  assert_equal 1, git.pushes
end

def test_each_mode_pushes_every_commit
  write_file("lib/ok.rb", "OK = 1\n")
  git = FakeGit.new([], ["lib/ok.rb"])
  with_push_env("each") { run_committer(git, FakeBus.new, "fix: ok") }

  assert_equal 1, git.pushes
end

def test_publish_pending_with_nothing_ahead_does_not_push
  git = FakeGit.new([], [])
  committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)

  assert_equal :nothing_to_publish, committer.publish_pending!
  assert_equal 0, git.pushes
end

def with_push_env(value)
  saved = ENV["MASTER_FIX_PUSH"]
  value ? ENV["MASTER_FIX_PUSH"] = value : ENV.delete("MASTER_FIX_PUSH")
  yield
ensure
  saved ? ENV["MASTER_FIX_PUSH"] = saved : ENV.delete("MASTER_FIX_PUSH")
end

# A lint that did not pass blocks the commit. Io::Exec answers a timed-out
  # rubocop with this same failed status; its own tests pin the timeout.
  def test_a_failed_lint_blocks_the_commit
    write_file("Gemfile", "source 'https://rubygems.org'\n")
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    bus = FakeBus.new
    failed = Struct.new(:success?).new(false)

    Master::Io::Exec.stub(:capture3, ["", "", failed]) { run_committer(git, bus, "fix: ok") }

    assert_empty git.commits
    assert blocked?(bus)
  end

  class BrokenBaselineGit < FakeGit
    def changed_paths
      raise "git status unavailable"
    end
  end

  def test_baseline_failure_blocks_the_transaction
    git = BrokenBaselineGit.new([], [])
    committer = Master::Fix::FixLoop::Committer.new(git:, bus: FakeBus.new, root: @dir)

    error = assert_raises(RuntimeError) { committer.baseline! }

    assert_match(/cannot establish fix transaction baseline: .*git status unavailable/, error.message)
  end

  # The lint step builds its command from Operator::RubyRunner. An unqualified constant inside
  # the Master namespace raised NameError, which the lint tests above read as 'rubocop
  # unavailable' and so passed for the wrong reason. With rubocop answering success the commit
  # has to go through, and the command has to be a real bundle exec.
  def test_a_passing_lint_lets_the_commit_through_and_builds_a_bundle_command
    write_file("Gemfile", "source 'https://rubygems.org'\n")
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    bus = FakeBus.new
    passed = Struct.new(:success?).new(true)
    seen = nil

    out, = capture_io do
      Master::Io::Exec.stub(:capture3, ->(*cmd, **) { seen = cmd; ["", "", passed] }) { run_committer(git, bus, "fix: ok") }
    end

    refute_includes out, "rubocop_unavailable"
    refute blocked?(bus)
    assert_equal 1, git.commits.size
    assert_includes seen, "rubocop"
    assert_includes seen, "exec"
  end

  def test_lint_command_exception_blocks_the_commit
    write_file("Gemfile", "source 'https://rubygems.org'\n")
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new([], ["lib/ok.rb"])
    bus = FakeBus.new

    Master::Io::Exec.stub(:capture3, ->(*) { raise "rubocop unavailable" }) do
      run_committer(git, bus, "fix: ok")
    end

    assert_empty git.commits
    assert blocked?(bus)
  end

  def test_nothing_is_committed_without_a_baseline
    write_file("lib/ok.rb", "OK = 1\n")
    git = FakeGit.new(["lib/ok.rb"], ["lib/ok.rb"])
    run_committer(git, FakeBus.new, "fix: ok", baseline: false)
    assert_empty git.commits
  end
end
