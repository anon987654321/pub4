# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

load File.expand_path("../../kernel/master.rb", __dir__)

class TestKernelSpine < Minitest::Test
  Model = Struct.new(:effects) do
    def propose(_context, verbs:)
      raise "missing verbs" unless verbs.include?(:done)

      effects.shift || Master::Effect.done("empty")
    end
  end

  def constitution
    Master::Constitution.load(data_dir: File.expand_path("../../data", __dir__))
  end

  def test_done_without_evidence_is_blocked
    Dir.mktmpdir do |dir|
      model = Model.new([Master::Effect.done("fake")])
      memory = Master::Memory.new
      world = Master::World.new(root: dir)

      result = Master::Kernel.new(
        model:,
        constitution: constitution,
        world:,
        memory:,
        max_turns: 1
      ).run("finish")

      assert_equal :max_turns, result.reason
      refute memory.proved?
    end
  end

  def test_exec_requires_structured_argv
    effect = Master::Effect.new(verb: :exec, args: { command: "echo unsafe" })
    verdict = constitution.admit(effect, Master::Memory.new)

    assert_kind_of Master::Verdict::Block, verdict
    assert_equal :structured_exec, verdict.by
  end

  def test_ruby_write_must_parse
    effect = Master::Effect.write("bad.rb", "def nope")
    verdict = constitution.admit(effect, Master::Memory.new)

    assert_kind_of Master::Verdict::Block, verdict
    assert_equal :ruby_parses, verdict.by
  end

  def test_world_blocks_path_escape
    Dir.mktmpdir do |dir|
      world = Master::World.new(root: dir)
      observation = world.perform(Master::Effect.read("../outside"))

      assert observation.err?
      assert_match(/path escapes workspace/, observation.message)
    end
  end

  def test_plain_success_is_not_evidence
    memory = Master::Memory.new
    memory.record(Master::Effect.exec(["true"]), Master::Observation.ok(""))

    refute memory.proved?
  end
end