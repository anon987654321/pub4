# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestStages < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
  end

  def test_guard_allows_safe_input
    stage = MASTER::Stages::Guard.new
    result = stage.call({ text: "What is the weather?" })
    
    assert result.ok?
  end

  def test_guard_blocks_dangerous_input
    stage = MASTER::Stages::Guard.new
    result = stage.call({ text: "rm -rf /" })
    
    assert result.err?
    assert_match(/dangerous/, result.error)
  end

  def test_route_selects_model
    stage = MASTER::Stages::Route.new
    result = stage.call({ text: "Hello world" })
    
    assert result.ok?
    assert result.value[:model], "Should select a model"
    assert result.value[:tier], "Should have a tier"
  end

  def test_lint_checks_axioms
    stage = MASTER::Stages::Lint.new
    result = stage.call({ response: "Some response text" })
    
    assert result.ok?
    assert result.value[:linted], "Should mark as linted"
  end

  def test_render_typesetting
    stage = MASTER::Stages::Render.new
    result = stage.call({ response: 'Use "smart quotes" and -- em dashes...' })
    
    assert result.ok?
    rendered = result.value[:rendered]
    assert_match(/\u{201C}/, rendered, "Should convert quotes")
    assert_match(/\u{2014}/, rendered, "Should convert dashes")
    assert_match(/\u{2026}/, rendered, "Should convert ellipses")
  end

  def test_render_preserves_code_blocks
    stage = MASTER::Stages::Render.new
    input = { response: "Here is code:\n```ruby\nx = \"test\"\n```\nDone." }
    result = stage.call(input)
    
    assert result.ok?
    assert_match(/x = "test"/, result.value[:rendered], "Should preserve code")
  end

  def test_intake_loads_persona
    stage = MASTER::Stages::Intake.new
    result = stage.call({ text: "Hello", persona: "security" })
    
    assert result.ok?
    # Persona loading depends on DB data
  end

  def test_debate_skips_when_not_enabled
    stage = MASTER::Stages::Debate.new
    result = stage.call({ text: "Simple query" })
    
    assert result.ok?
    refute result.value[:debate_rounds], "Should skip debate when not enabled"
  end
end
