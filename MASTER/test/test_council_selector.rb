# frozen_string_literal: true

require_relative "test_helper"

# The council's front door, and every existing test called it one way.
#
# test_council_personas and test_dilla_council both do
# `Selector.for(task: :ui)` and `Selector.for(task: :sonic)`. Neither ever
# passed a risk, and neither ever passed `available:` -- so the class had two
# defects that only the untried arguments could show:
#
#   task AND risk        raised NoMethodError. `base_personas` ended in a
#                        trailing `if task_set.nil? || risk_set.nil?`, which
#                        guards the whole expression, so having both returned
#                        nil and `select` called nil + ALWAYS_INCLUDED.
#   available:           was inert. `normalize_available` was `nil unless
#                        available`, which returns nil whether or not a list was
#                        given, so the filter in #select never ran and a caller
#                        got back personas it had told the selector it did not
#                        have.
class TestCouncilSelector < Minitest::Test
  S = Master::Review::Council::Selector

  # --- the two axes, together and apart ------------------------------------

  def test_a_task_selects_the_people_who_understand_the_change
    names = S.for(task: :ui)

    assert_includes names, "Typographer"
    assert_includes names, "Accessibility"
  end

  def test_a_risk_selects_the_people_who_must_sign_it_off
    assert_equal %w[Security Reliability Maintainer Skeptic].sort, S.for(risk: :high).sort
  end

  # The call the class exists for, and the one nothing made.
  def test_both_axes_together_do_not_raise
    names = S.for(task: :ui, risk: :critical)

    refute_nil names
    refute_empty names
  end

  # Union rather than a precedence: the task says who understands the change and
  # the risk says who signs it off, and those are different questions.
  def test_both_axes_together_seat_both_sets
    names = S.for(task: :docs, risk: :critical)

    assert_includes names, "Layperson", "the task's own people were dropped"
    assert_includes names, "Security", "the risk floor was dropped"
    assert_includes names, "Chaos"
  end

  def test_nobody_is_seated_twice
    names = S.for(task: :security_audit, risk: :critical)

    assert_equal names.uniq, names
  end

  def test_the_maintainer_is_always_in_the_room
    [
      {}, { task: :ui }, { risk: :low }, { task: :docs, risk: :critical },
      { task: :not_a_task }, { risk: :not_a_risk },
    ].each do |arguments|
      assert_includes S.for(**arguments), "Maintainer", "no maintainer for #{arguments.inspect}"
    end
  end

  def test_an_unknown_task_or_risk_falls_back_rather_than_raising
    assert_equal ["Maintainer"], S.for(task: :not_a_task)
    assert_equal ["Maintainer"], S.for(risk: :not_a_risk)
    assert_equal ["Maintainer"], S.for
  end

  def test_a_task_may_be_named_as_a_string_or_a_symbol
    assert_equal S.for(task: :ui).sort, S.for(task: "ui").sort
    assert_equal S.for(risk: :high).sort, S.for(risk: "high").sort
  end

  # --- the available filter ------------------------------------------------

  def test_the_available_list_narrows_the_result
    names = S.for(task: :ui, available: ["Maintainer", "Typographer"])

    assert_equal %w[Maintainer Typographer].sort, names.sort
  end

  def test_a_persona_that_is_not_available_is_not_seated
    refute_includes S.for(task: :ui, available: ["Maintainer"]), "Typographer"
  end

  # Not even the always-included one: an empty roster means there is nobody to
  # convene, and inventing a Maintainer the caller has said it does not have is
  # how a council names a persona that cannot answer.
  def test_an_empty_roster_seats_nobody
    assert_empty S.for(task: :ui, available: [])
  end

  def test_no_available_list_means_no_filtering
    assert_equal S.for(task: :ui), S.for(task: :ui, available: nil)
  end

  def test_the_roster_may_be_given_as_symbols
    assert_includes S.for(task: :ui, available: [:Maintainer]), "Maintainer"
  end

  def test_an_available_persona_nobody_asked_for_is_not_added
    refute_includes S.for(task: :docs, available: ["Maintainer", "Chaos"]), "Chaos"
  end

  # --- the tables ----------------------------------------------------------

  def test_every_task_seats_somebody
    S::TASK_PERSONAS.each do |task, personas|
      refute_empty personas, "#{task} convenes an empty council"
      assert_equal personas.uniq, personas, "#{task} lists a persona twice"
    end
  end

  def test_every_risk_level_seats_somebody_and_they_nest
    levels = %i[low medium high critical]
    sets = levels.map { |level| S::RISK_PERSONAS.fetch(level) }

    sets.each_cons(2) do |lower, higher|
      assert_empty lower - higher, "a higher risk level drops someone a lower one required: #{(lower - higher).inspect}"
    end
  end

  def test_every_declared_task_is_reachable_through_the_public_entry
    S::TASK_PERSONAS.each_key do |task|
      names = S.for(task:)
      assert_operator names.size, :>, 1, "#{task} resolves to the fallback, so its row is unreachable"
    end
  end

  def test_every_declared_risk_is_reachable_through_the_public_entry
    S::RISK_PERSONAS.each_key do |risk|
      refute_empty S.for(risk:), "#{risk} resolves to nothing"
    end
  end

  # Every name in either table must be a persona the council actually has, or
  # the selector seats someone who cannot speak.
  # There are two populations of reviewer in this tree and the selector must draw
  # from only one of them.
  #
  # data/council.yml holds the personas; lib/review/review_crew/ holds a separate
  # set of reviewers as agent classes — architecture, chaos, minimalist,
  # performance, security, style. "Chaos" and "Minimalist" were in the second and
  # not the first, so `Selector.for(task: :architecture)` and every critical-risk
  # selection named two reviewers the council could not seat. Both are gone from
  # these tables now, replaced by Pragmatist, which is a real persona.
  #
  # A crew agent's name reappearing here is that defect returning, so it is
  # asserted from both directions: every name must be a persona, and no name may
  # be a crew agent that is not also one.
  def crew_agents
    Dir.glob(File.expand_path("../lib/review/review_crew/*_agent.rb", __dir__))
       .map { |path| File.basename(path, "_agent.rb").capitalize }
  end

  def selector_names
    (S::TASK_PERSONAS.values + S::RISK_PERSONAS.values).flatten.uniq + S::ALWAYS_INCLUDED
  end

  def test_every_named_persona_exists
    known = Master::Review::Council::Personas.load.map(&:name)
    refute_empty known, "the persona registry loaded nothing, so this test proves nothing"

    missing = selector_names.uniq - known

    assert_empty missing,
                 "the selector seats reviewers data/council.yml does not have. If these are " \
                 "review_crew agent classes, they belong to the other registry: #{missing.inspect}"
  end

  def test_no_review_crew_agent_is_named_as_a_persona
    known = Master::Review::Council::Personas.load.map(&:name)
    borrowed = (selector_names.uniq & crew_agents) - known

    assert_empty borrowed,
                 "a review_crew agent name is back in the persona tables: #{borrowed.inspect}"
  end
end
