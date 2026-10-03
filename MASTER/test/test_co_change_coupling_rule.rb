# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

# The rule reads a co-change graph and reports files that move with peers in
# other modules. Its whole judgement is three filters — same module, weight
# below the threshold, and everything past the top three — so each is asserted
# in both directions here. A rule tested only for "returns an Array" passes with
# every filter inverted.
#
# The graph is injected. Anything answering co_change_graph is an ecology as far
# as this rule is concerned, so the test needs no repository history and states
# the coupling it is judging rather than hoping the tree contains one.
class TestCoChangeCouplingRule < Minitest::Test
  Rules = Master::Review::Scan::Rules
  ROOT = "/repo"

  # Paths are relative to a module_of that treats MASTER specially: under
  # MASTER the module is the third segment, elsewhere the first.
  SUBJECT = "#{ROOT}/MASTER/lib/voice/speech.rb"
  OTHER_MODULE = "MASTER/lib/review/scanner.rb"
  SAME_MODULE = "MASTER/lib/voice/engines.rb"

  def rule(graph)
    ecology = Struct.new(:co_change_graph).new(graph)
    Rules::CoChangeCouplingRule.new(root: ROOT, ecology:)
  end

  def messages(graph, path: SUBJECT)
    rule(graph).check("", path:).map(&:message)
  end

  def test_a_cross_module_peer_at_the_threshold_is_reported_with_its_weight
    found = messages({ "MASTER/lib/voice/speech.rb" => { OTHER_MODULE => 5 } })

    assert_equal 1, found.size
    assert_includes found.first, OTHER_MODULE
    assert_includes found.first, "(5)", "the weight is the evidence — reporting the peer without it says nothing"
  end

  def test_a_peer_below_the_threshold_is_not_reported
    assert_empty messages({ "MASTER/lib/voice/speech.rb" => { OTHER_MODULE => 4 } })
  end

  # The rule is about coupling across module boundaries. Files in one module
  # moving together is cohesion, which is the thing it must not flag.
  def test_a_same_module_peer_is_never_reported_however_heavy
    assert_empty messages({ "MASTER/lib/voice/speech.rb" => { SAME_MODULE => 500 } })
  end

  def test_at_most_three_peers_are_named_and_the_heaviest_come_first
    peers = { "MASTER/lib/a/one.rb" => 6, "MASTER/lib/b/two.rb" => 9,
              "MASTER/lib/c/three.rb" => 7, "MASTER/lib/d/four.rb" => 8 }
    found = messages({ "MASTER/lib/voice/speech.rb" => peers })

    assert_equal 1, found.size
    assert_includes found.first, "3 peer(s)"
    refute_includes found.first, "one.rb", "the lightest of four must be the one dropped"
    assert_operator found.first.index("two.rb"), :<, found.first.index("three.rb"),
                    "peers are ordered by weight, heaviest first"
  end

  def test_a_file_with_no_recorded_peers_is_silent
    assert_empty messages({})
  end

  # Two guard clauses, both cheap and both load-bearing: the rule reads Ruby
  # co-change only, and a path outside the root has no relative name to key the
  # graph by.
  def test_a_non_ruby_path_is_skipped
    assert_empty messages({ "MASTER/lib/voice/speech.rb" => { OTHER_MODULE => 50 } },
                          path: "#{ROOT}/MASTER/lib/voice/speech.scss")
  end

  def test_a_path_outside_the_root_is_skipped
    assert_empty messages({ "MASTER/lib/voice/speech.rb" => { OTHER_MODULE => 50 } },
                          path: "/elsewhere/MASTER/lib/voice/speech.rb")
  end

  # The scanner registry and rules.yml both key on the id, and rule_deps orders
  # by it, so a rename that misses one of them is a rule that silently stops
  # being weighted. Cheap to pin, and it is the string those tables carry.
  def test_it_registers_under_the_id_the_dependency_graph_names
    assert_equal "co_change_coupling", rule({}).id.to_s
  end
end
