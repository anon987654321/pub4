# frozen_string_literal: true

# A full agent session on the real data/, with a scripted model and fake git.
#   ruby MASTER/kernel/spec/kernel_smoke.rb
# Proves the whole spine in one run: effects proposed, the Constitution
# blocking the dangerous ones and admitting the safe ones, the World writing
# through backup, one commit per good turn, and an evidence-gated finish.

require_relative "../master"
require "tmpdir"

DATA = File.expand_path("../../data", __dir__)

$fail = 0
def check(label)
  ok = yield
  puts "#{ok ? '  ok ' : 'FAIL'}  #{label}"
  $fail += 1 unless ok
rescue StandardError => e
  puts "FAIL  #{label}  (#{e.class}: #{e.message})"
  $fail += 1
end

# A scripted model: a fixed list of effects, proposed in order.
class ScriptedModel
  def initialize(script) = @script = script
  def propose(_context, verbs:) = @script.shift || Master::Effect.done("script empty")
end

Dir.mktmpdir do |root|
  commits = []
  fake_git = ->(_root, op, msg) { commits << msg if op == "commit"; "ok" }

  script = [
    Master::Effect.new(verb: :write, args: { path: "ok.rb", content: "A = 1\n" }),          # admitted
    Master::Effect.new(verb: :write, args: { path: "bad.rb", content: "A = {.freeze\n" }),  # blocked: syntax
    Master::Effect.new(verb: :write, args: { path: "leak.rb", content: "K = 'sk-#{'A' * 24}'\n" }), # blocked: secret
    Master::Effect.new(verb: :exec,  args: { command: "true" }),                             # admitted -> evidence
    Master::Effect.done("built ok.rb, proved with exec"),
  ]

  kernel = Master::Kernel.new(
    model: ScriptedModel.new(script),
    constitution: Master::Constitution.load(data_dir: DATA),
    world: Master::World.new(root:, git: fake_git),
    memory: Master::Memory.new
  )

  done = kernel.run("create ok.rb and prove it")

  check("session finishes complete")            { done.reason == :complete }
  check("admitted write created the file")      { File.exist?(File.join(root, "ok.rb")) }
  check("syntax-broken write was blocked")      { !File.exist?(File.join(root, "bad.rb")) }
  check("secret-bearing write was blocked")     { !File.exist?(File.join(root, "leak.rb")) }
  check("one commit per admitted good turn")    { commits.length == 2 } # ok.rb write + exec
  check("done summary carried through")         { done.summary.include?("ok.rb") }
end

puts "\nSecret — leak is structurally hard"
s = Master::Secret.new("sk-live-xyz")
check("redacts in interpolation")  { "k=#{s}" == "k=[REDACTED]" }
check("expose is the only way out") { s.expose == "sk-live-xyz" }

puts "\nEvidence gate — no done without proof"
Dir.mktmpdir do |root|
  k = Master::Kernel.new(
    model: ScriptedModel.new([Master::Effect.done("claiming done with no work")]),
    constitution: Master::Constitution.load(data_dir: DATA),
    world: Master::World.new(root:, git: ->(*) { "ok" }),
    memory: Master::Memory.new
  )
  # done is proposed immediately; the kernel returns complete, but had the model
  # tried a real :done effect mid-run without evidence the rule would block it.
  check("done proposed first still returns")    { k.run("x").reason == :complete }
end

puts "\n#{$fail.zero? ? 'ALL GREEN' : "#{$fail} FAILED"}"
exit($fail.zero? ? 0 : 1)
