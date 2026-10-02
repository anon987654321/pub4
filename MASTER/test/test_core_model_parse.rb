# frozen_string_literal: true

require "minitest/autorun"
require "master"

# Model.parse is the whole trust boundary between the LLM and the fold: it must
# turn any string into exactly one Effect, and never raise. These cases pin that.
class TestModelParse < Minitest::Test
  VERBS = Master::Core::VERBS

  def parse(text) = Master::Core::Model.parse(text, verbs: VERBS)

  def test_clean_write_effect
    e = parse('{"verb":"write","args":{"path":"a.rb","content":"A = 1\n"}}')
    assert_equal :write, e.verb
    assert_equal "a.rb", e.args[:path]
    assert_equal "A = 1\n", e.args[:content]
  end

  def test_done_effect
    e = parse('{"verb":"done","args":{"summary":"built it"}}')
    assert e.done?
    assert_equal "built it", e.args[:summary]
  end

  def test_exec_with_array_argv
    e = parse('{"verb":"exec","args":{"argv":["rake","test"],"evidence":"test_pass"}}')
    assert_equal :exec, e.verb
    assert_equal %w[rake test], e.args[:argv]
    assert_equal "test_pass", e.args[:evidence]
  end

  def test_json_embedded_in_prose_is_extracted
    e = parse("Sure, here is the next step:\n{\"verb\":\"read\",\"args\":{\"path\":\"x\"}}\nThat reads it.")
    assert_equal :read, e.verb
    assert_equal "x", e.args[:path]
  end

  def test_json_in_a_code_fence_is_parsed
    e = parse("```json\n{\"verb\":\"read\",\"args\":{\"path\":\"lib/a.rb\"}}\n```")
    assert_equal :read, e.verb
    assert_equal "lib/a.rb", e.args[:path]
  end

  def test_write_with_braces_in_content_survives
    e = parse('{"verb":"write","args":{"path":"a.rb","content":"def f = { a: 1 }\n"}}')
    assert_equal :write, e.verb
    assert_equal "def f = { a: 1 }\n", e.args[:content]
  end

  def test_unknown_verb_becomes_note_not_crash
    e = parse('{"verb":"launch_missiles","args":{}}')
    assert_equal :note, e.verb
    assert_match(/unknown verb/, e.args[:text])
  end

  def test_no_json_becomes_note
    e = parse("I am not sure what to do next.")
    assert_equal :note, e.verb
    assert_match(/no JSON/, e.args[:text])
  end

  def test_malformed_json_becomes_note
    e = parse('{"verb":"write","args":{ oops }')
    assert_equal :note, e.verb
  end

  def test_missing_args_defaults_to_empty
    e = parse('{"verb":"done"}')
    assert e.done?
    assert_nil e.args[:summary]
  end

  def test_non_hash_args_do_not_raise
    e = parse('{"verb":"exec","args":[1]}')
    assert_equal :exec, e.verb
    assert_equal({}, e.args)
  end
end

# The reply schema is built per turn from Proof#scope. A verb whose
# precondition fails is not in the enum, so a schema-bound model cannot write
# it; these read the offer off real Proof states rather than hand-built hashes.
class TestModelOffer < Minitest::Test
  Effect = Master::Core::Effect
  Observation = Master::Core::Observation

  def offered(proof) = Master::Core::Model.offer(Master::Core::VERBS, proof.scope)
  def verbs(schema) = schema.dig(:properties, :verb, :enum)
  def operations(schema) = schema.dig(:properties, :args, :properties, :operation, :enum)

  def test_a_fresh_goal_cannot_be_offered_done_or_a_commit
    schema = offered(Master::Core::Proof.new)
    refute_includes verbs(schema), "done"
    refute_includes operations(schema), "commit"
    assert_includes verbs(schema), "read"
    assert_includes verbs(schema), "write"
  end

  def test_a_read_answers_so_done_opens
    proof = Master::Core::Proof.new
    proof.record_evidence(Effect.read("notes.md"), Observation.ok("hello"))
    assert_includes verbs(offered(proof)), "done"
  end

  def test_evidence_opens_done_and_commit
    proof = Master::Core::Proof.new
    proof.record_evidence(Effect.write("a.rb", "A = 1\n"), Observation.ok)
    refute_includes verbs(offered(proof)), "done", "a write with no proof since is a claim nobody checked"
    { test_pass: %w[rake test], scan_clean: %w[rubocop], code_review: %w[rake review] }.each do |kind, argv|
      proof.record_evidence(Effect.exec(argv, evidence: kind), Observation.ok("ok"))
    end
    assert_includes verbs(offered(proof)), "done"
    assert_includes operations(offered(proof)), "commit"
  end

  def test_pending_ideation_closes_write_and_high_risk_closes_done_until_council
    proof = Master::Core::Proof.new(risk: :high)
    proof.record_evidence(Effect.read("notes.md"), Observation.ok("hello"))
    refute_includes verbs(offered(proof)), "write"
    refute_includes verbs(offered(proof)), "done"
    proof.mark_ideation_complete!
    proof.mark_council_pass!
    assert_includes verbs(offered(proof)), "write"
    assert_includes verbs(offered(proof)), "done"
  end

  def test_no_scope_offers_everything
    assert_equal Master::Core::Model::SCHEMA, Master::Core::Model.offer(Master::Core::VERBS, nil)
  end
end

# llama.cpp turns a JSON schema into a grammar and reads an object that names
# properties and is silent on the rest as closed. Measured on gemma3:4b: args
# that named only `operation` came back {"operation":"stage"} for a read.
class TestModelSchemaArgsStayOpen < Minitest::Test
  def test_args_accept_keys_the_schema_does_not_name
    schema = Master::Core::Model.offer(Master::Core::VERBS, Master::Core::Proof.new.scope)
    assert_equal true, schema.dig(:properties, :args, :additionalProperties)
  end
end
