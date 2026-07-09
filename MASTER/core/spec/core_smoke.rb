# frozen_string_literal: true

# A full agent session on the real data/, with a scripted model and real git.
#   ruby MASTER/core/spec/core_smoke.rb
# Proves the whole spine in one run: effects proposed, the Constitution
# blocking the dangerous ones and admitting the safe ones, the World writing
# through backup, explicit git commit after evidence, and an evidence-gated finish.

require_relative "../master"
require "open3"
require "tmpdir"

DATA = File.expand_path("../../data", __dir__)

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

# A scripted model: a fixed list of effects, proposed in order.
class ScriptedModel
  def initialize(script) = @script = script
  def propose(_context, verbs:) = @script.shift || Master::Core::Effect.done("script empty")
end

Dir.mktmpdir do |root|
  init_git!(root)

  script = [
    Master::Core::Effect.write("ok.rb", "A = 1\n"),
    Master::Core::Effect.new(verb: :write, args: { path: "bad.rb", content: "A = {.freeze\n" }),
    Master::Core::Effect.new(verb: :write, args: { path: "leak.rb", content: "K = 'sk-#{'A' * 24}'\n" }),
    Master::Core::Effect.exec(["true"], evidence: :test_pass),
    Master::Core::Effect.exec(["true"], evidence: :scan_clean),
    Master::Core::Effect.exec(["true"], evidence: :code_review),
    Master::Core::Effect.git(:stage, paths: ["ok.rb"]),
    Master::Core::Effect.git(:commit, message: "add ok.rb"),
    Master::Core::Effect.done("built ok.rb, proved with exec"),
  ]

  core = Master::Core::Fold.new(
    model: ScriptedModel.new(script),
    constitution: Master::Core::Constitution.load(data_dir: DATA),
    world: Master::Core::World.new(root:),
    memory: Master::Core::Memory.new
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
    max_turns: 1
  )
  check("done without evidence is blocked") { k.run("x").reason == :max_turns }
end

puts $fail.zero? ? "\nok: core smoke passed" : "\nwarn: core smoke #{$fail} failed"
exit($fail.zero? ? 0 : 1)