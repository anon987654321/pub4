require 'minitest/autorun'
require_relative '../lib/engine'
require_relative '../lib/llm'

class TestMASTER2 < Minitest::Test
  def setup
    @engine = MASTER::Engine.new
    @code = "def hello; puts 'hi'; end"
  end

  def test_refactor_success
    result = @engine.refactor(@code)
    assert result[:success]
    refute_empty result[:diff]
  end

  def test_large_file
    large = @code * 2000
    result = @engine.refactor(large)
    refute result[:success]
    assert_match /too large/, result[:error]
  end

  def test_offline
    ENV['OFFLINE'] = '1'
    result = @engine.refactor(@code)
    assert result[:success]
    ENV.delete 'OFFLINE'
  end

  def test_js_stub
    js_code = "function hello() { console.log('hi'); }"
    result = @engine.refactor(js_code, 'javascript')
    assert_kind_of Hash, result
    assert result[:code].include? 'hello'
  end
end
