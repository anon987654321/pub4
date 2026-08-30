# frozen_string_literal: true

# A full agent session on the real data/, with a scripted model and real git.
#   ruby -IMASTER/lib MASTER/spec/core_smoke.rb
# Proves the whole spine in one run: effects proposed, the Constitution
# blocking the dangerous ones and admitting the safe ones, the World writing
# through backup, explicit git commit after evidence, and an evidence-gated finish.

require "master"
require "open3"
require "tmpdir"

DATA = File.expand_path("../data", __dir__)

$fail = 0
def check(label)
  ok = yield
  puts "#{ok ? 'ok:' : 'warn:'} #{label}"
  $fail += 1 unless ok
rescue StandardError => e
  puts "warn: #{label} (#{e.class}: #{e.message})"
  $fail += 1
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
# fold grade its own paper. The fixture has to satisfy that binding.
#
# An argv that merely *matches* the pattern reopens the same hole one level
# down. These are files that run and exit 0, the smallest honest thing that
# produces each kind.
#
# This spec is easy to miss. `rake spec` globs spec/**/*_spec.rb and this name
# does not match, so reaching it takes `rake core_smoke` — which `rake audit`,
# bin/ci and bin/probe run, and of bin/check's profiles only `full`. Operator,
# contributor and agent are the profiles in daily use.
def seed_producers!(root)
  File.write(File.join(root, "Rakefile"), "task(:test) { }\n")
  Dir.mkdir(File.join(root, "test"))
  File.write(File.join(root, "test", "ok_test.rb"), <<~RUBY)
    raise "smoke fixture: A should be 1" unless eval(File.read("ok.rb")) == 1
  RUBY
  Dir.mkdir(File.join(root, "bin"))
  # bin/check produces scan_clean, bin/review produces code_review -- the kinds
  # the exec effects below claim, and what PRODUCERS binds those names to.
  %w[check review].each do |name|
    path = File.join(root, "bin", name)
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, path)
  end
end

# A scripted model: a fixed list of effects, proposed in order.
class ScriptedModel
  def initialize(script) = @script = script
  def propose(_context, verbs:) = @script.shift || Master::Core::Effect.done("script empty")
end

Dir.mktmpdir do |root|
  init_git!(root)
  seed_producers!(root)

  # Writes come before the execs because a write bumps the proof's generation,
  # and evidence only counts for the generation it was earned in -- proving a
  # tree and then rewriting it is not proof of the tree that shipped.
  script = [
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

  core = Master::Core::Fold.new(
    model: ScriptedModel.new(script),
    constitution: Master::Core::Constitution.load(data_dir: DATA),
    world: Master::Core::World.new(root:),
    memory: Master::Core::Memory.new,
  )

  done = core.run("create ok.rb and prove it")

  check("session finishes complete")            { done.reason == :complete }
  check("admitted write created the file")      { File.exist?(File.join(root, "ok.rb")) }
  check("syntax-broken write was blocked")      { !File.exist?(File.join(root, "bad.rb")) }
  check("secret-bearing write was blocked")     { !File.exist?(File.join(root, "leak.rb")) }
  check("evidence-gated commit landed")         { commit_count(root) == 1 }
  check("done summary carried through")         { done.summary.include?("ok.rb") }
end

puts "\nSecret — leak is structurally hard"
s = Master::Core::Secret.new("sk-live-xyz")
check("redacts in interpolation")  { "k=#{s}" == "k=[REDACTED]" }
check("expose is the only way out") { s.expose == "sk-live-xyz" }

puts "\nEvidence gate — no done without proof"
Dir.mktmpdir do |root|
  init_git!(root)
  k = Master::Core::Fold.new(
    model: ScriptedModel.new([Master::Core::Effect.done("claiming done with no work")]),
    constitution: Master::Core::Constitution.load(data_dir: DATA),
    world: Master::Core::World.new(root:),
    memory: Master::Core::Memory.new,
    max_turns: 1,
  )
  check("done without evidence is blocked") { k.run("x").reason == :max_turns }
end

puts $fail.zero? ? "\nok: core smoke passed" : "\nwarn: core smoke #{$fail} failed"
exit($fail.zero? ? 0 : 1)
