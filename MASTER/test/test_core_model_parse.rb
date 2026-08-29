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
