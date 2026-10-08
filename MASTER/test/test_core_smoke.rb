# frozen_string_literal: true

# A full agent session on the real data/, with a scripted model and real git.
#   ruby -IMASTER/lib MASTER/test/test_core_smoke.rb
# Proves the whole spine in one run: effects proposed, the Constitution
# blocking the dangerous ones and admitting the safe ones, the World writing
# through backup, explicit git commit after evidence, and an evidence-gated finish.
#
# This Minitest file is reached by `rake core_smoke`, the default suite, bin/ci and bin/probe core.

require "minitest/autorun"
require "master"
require "open3"
require "tmpdir"

class CoreSmokeTest < Minitest::Test
  DATA = File.expand_path("../data", __dir__)

  # A scripted model: a fixed list of effects, proposed in order.
  class ScriptedModel
    def initialize(script) = @script = script
    def propose(_context, verbs:, **) = @script.shift || Master::Core::Effect.done("script empty")
  end

  def test_a_session_admits_safe_effects_blocks_dangerous_ones_and_commits_on_evidence
    Dir.mktmpdir do |root|
      init_git!(root)
      seed_producers!(root)

      done = fold(root, session_script).run("create ok.rb and prove it")

      assert_equal :complete, done.reason
      assert File.exist?(File.join(root, "ok.rb")), "the admitted write created no file"
      refute File.exist?(File.join(root, "bad.rb")), "the syntax-broken write landed"
      refute File.exist?(File.join(root, "leak.rb")), "the secret-bearing write landed"
      assert_equal 1, commit_count(root), "the evidence-gated commit did not land"
      assert_includes done.summary, "ok.rb"
    end
  end

  def test_a_secret_redacts_in_interpolation_and_exposes_only_on_request
    secret = Master::Core::Secret.new("sk-live-xyz")

    assert_equal "k=[REDACTED]", "k=#{secret}"
    assert_equal "sk-live-xyz", secret.expose
  end

  def test_done_without_evidence_is_blocked
    Dir.mktmpdir do |root|
      init_git!(root)
      model = ScriptedModel.new([Master::Core::Effect.done("claiming done with no work")])

      assert_equal :max_turns, fold(root, nil, model:, max_turns: 1).run("x").reason
    end
  end

  private

  # Writes come before the execs because a write bumps the proof's generation,
  # and evidence only counts for the generation it was earned in -- proving a
  # tree and then rewriting it is not proof of the tree that shipped.
  def session_script
    [
      Master::Core::Effect.write("ok.rb", "A = 1\n"),
      Master::Core::Effect.new(verb: :write, args: { path: "bad.rb", content: "A = {.freeze\n" }),
      Master::Core::Effect.new(verb: :write, args: { path: "leak.rb", content: "K = 'sk-#{'A' * 24}'\n" }),
      Master::Core::Effect.exec(%w[ruby test/ok_test.rb], evidence: :test_pass),
      Master::Core::Effect.exec(%w[bin/check], evidence: :scan_clean),
      Master::Core::Effect.exec(%w[bin/review], evidence: :code_review),
      Master::Core::Effect.git(:stage, paths: ["ok.rb"]),
      # Paths, because git_commit_scope blocks an unscoped commit: `git commit -m`
      # takes the whole index, which in this repo is shared with other sessions.
      Master::Core::Effect.git(:commit, message: "add ok.rb", paths: ["ok.rb"]),
      Master::Core::Effect.done("built ok.rb, proved with exec"),
    ]
  end

  def fold(root, script, model: ScriptedModel.new(script), max_turns: nil)
    options = {
      model:,
      constitution: Master::Core::Constitution.load(data_dir: DATA),
      world: Master::Core::World.new(root:),
      memory: Master::Core::Memory.new,
    }
    options[:max_turns] = max_turns if max_turns
    Master::Core::Fold.new(**options)
  end

  def init_git!(root)
    system("git", "-C", root, "init", "-q")
    system("git", "-C", root, "config", "user.email", "smoke@test.local")
    system("git", "-C", root, "config", "user.name", "core smoke")
  end

  def commit_count(root)
    out, status = Open3.capture2e("git", "-C", root, "log", "--oneline")
    status.success? ? out.lines.count : 0
  end

  # A miniature repo for the fold to earn its evidence in.
  #
  # Proof::PRODUCERS binds each evidence kind to the commands that can produce it,
  # so `exec(["true"])` scores nothing: awarding 35 points for `true` lets the
  # fold grade its own paper. These are files that run and exit 0, the smallest
  # honest thing that produces each kind.
  def seed_producers!(root)
    File.write(File.join(root, "Rakefile"), "task(:test) { }\n")
    Dir.mkdir(File.join(root, "test"))
    File.write(File.join(root, "test", "ok_test.rb"), <<~RUBY)
      raise "smoke fixture: A should be 1" unless eval(File.read("ok.rb")) == 1
    RUBY
    Dir.mkdir(File.join(root, "bin"))
    # bin/check produces scan_clean, bin/review produces code_review -- the kinds
    # the exec effects claim, and what PRODUCERS binds those names to.
    %w[check review].each do |name|
      path = File.join(root, "bin", name)
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
    end
  end
end
