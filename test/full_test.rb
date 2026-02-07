require 'minitest/autorun'
require_relative '../lib/engine'
require_relative '../lib/llm'

class TestMASTER2 < Minitest::Test
  def setup
    @engine = MASTER::Engine.new
    @code = "def hello; puts 'hi'; end"
  end

  def test_refactor
    result = @engine.refactor(@code)
    assert result[:success]
    refute_empty result[:diff]
  end

  def test_analyze
    analysis = @engine.analyze(@code)
    assert analysis[:suggestions]
  end

  def test_llm_error_handling
    MASTER::LLM.any_instance.stubs(:call_api).returns({ 'error' => 'test' })
    result = @engine.refactor(@code)
    assert !result[:success]
  end

  def test_multi_lang_stub
    js_code = "function hello() { console.log('hi'); }"
    result = @engine.refactor(js_code, 'javascript')
    assert_kind_of Hash, result
  end
end
