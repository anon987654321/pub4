# frozen_string_literal: true

require "minitest/autorun"
require "master"
require "tmpdir"

# Verdict::Request is the fourth answer the Constitution can give: a person
# decides. World#do_ask existed long before any rule could reach it, so an
# effect that is dangerous in one context and routine in another had to be
# allowed or refused once, for every context.
class RequestVerdictTest < Minitest::Test
  C = Master::Core
  E = C::Effect

  # Answers whatever it is told to, and records what it was asked.
  class Surface
    attr_reader :prompts

    def initialize(answer) = (@answer = answer; @prompts = [])

    def call(prompt:, options: nil)
      @prompts << prompt
      @answer
    end
  end

  def law(sandbox)
    C::Constitution.new(rules: [C::Constitution.send(:sandboxed_exec_rule, sandbox)])
  end

  def effect = E.exec(%w[rm -rf /tmp/scratch])

  def test_a_deny_string_still_blocks
    verdict = law(->(_argv) { "dangerous rm" }).admit(effect, nil)

    assert_kind_of C::Verdict::Block, verdict
    assert_includes verdict.reason, "dangerous rm"
  end

  def test_nil_still_falls_through_to_allow
    assert_kind_of C::Verdict::Allow, law(->(_argv) { nil }).admit(effect, nil)
  end

  def test_an_ask_hash_becomes_a_request_naming_the_command
    verdict = law(->(_argv) { { ask: "removes a directory" } }).admit(effect, nil)

    assert_kind_of C::Verdict::Request, verdict
    assert_equal :sandboxed_exec, verdict.by
    assert_includes verdict.prompt, "rm -rf /tmp/scratch"
    assert_includes verdict.prompt, "removes a directory"
  end

  # The rules after this one would be judging an effect nobody has agreed to.
  def test_a_request_returns_immediately_and_is_not_revised_further
    later = C::Constitution::Rule.new(
      id: :never_reached, verbs: %i[exec],
      judge: ->(_e, _m) { raise "a later rule ran after a Request" },
    )
    law = C::Constitution.new(
      rules: [C::Constitution.send(:sandboxed_exec_rule, ->(_argv) { { ask: "check" } }), later],
    )

    assert_kind_of C::Verdict::Request, law.admit(effect, nil)
  end

  def with_fold(answer, sandbox:)
    Dir.mktmpdir do |root|
      world = C::World.new(root:, ask: Surface.new(answer))
      yield world, law(sandbox)
    end
  end

  def test_an_approved_request_performs_the_effect
    with_fold("yes", sandbox: ->(_argv) { { ask: "check" } }) do |world, _law|
      assert world.perform(E.ask("run it?")).ok?
    end
  end

  # No surface to ask is a no. The rule already judged this worth interrupting
  # for, so proceeding unattended is the one thing it must not do.
  def test_no_surface_to_ask_is_a_refusal_not_a_pass
    Dir.mktmpdir do |root|
      world = C::World.new(root:)
      answer = world.perform(E.ask("run it?"))

      refute answer.ok?
      assert_includes answer.detail.to_s, "no surface to ask"
    end
  end

  def test_the_operator_is_asked_the_rules_own_question
    surface = Surface.new("no")
    Dir.mktmpdir do |root|
      world = C::World.new(root:, ask: surface)
      verdict = law(->(_argv) { { ask: "removes a directory" } }).admit(effect, nil)
      world.perform(E.ask(verdict.prompt))
    end

    assert_includes surface.prompts.first, "removes a directory"
  end
end
