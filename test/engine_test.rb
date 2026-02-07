require 'minitest/autorun'
require_relative '../lib/engine'

class TestEngine < Minitest::Test
  def test_refactor
    engine = MASTER::Engine.new
    code = "def hello; puts 'hi'; end"
    result = engine.refactor(code)
    assert result[:success]
  end

  def test_analyze
    engine = MASTER::Engine.new
    code = "def hello; puts 'hi'; end"
    analysis = engine.analyze(code)
    assert analysis[:suggestions]
  end
end
