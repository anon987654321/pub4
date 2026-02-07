require 'minitest/autorun'
require_relative '../lib/engine'
require_relative '../lib/llm'
require_relative '../lib/autonomy'
require_relative '../lib/persistence'

class TestMASTER2 < Minitest::Test
  def setup
    @engine = MASTER::Engine.new
    @code = "def hello; puts 'hi'; end"
    @js_code = "function hello() { console.log('hi'); }"
    @py_code = "def hello(): print('hi')"
  end

  def test_refactor_ruby
    result = @engine.refactor(@code)
    assert result[:success]
    refute_empty result[:diff]
  end

  def test_analyze_ruby
    analysis = @engine.analyze(@code)
    assert analysis[:suggestions].size > 0
  end

  def test_multi_lang_js
    result = @engine.refactor(@js_code, 'javascript')
    assert_kind_of Hash, result
    assert result[:code].include? 'hello'
  end

  def test_multi_lang_py
    result = @engine.analyze(@py_code, 'python')
    assert result[:suggestions]
  end

  def test_autonomy_decision
    autonomy = MASTER::Autonomy.new
    assert_equal :apply, autonomy.decide(:refactor, 'low')
    assert_equal :ask, autonomy.decide(:refactor, 'high')
  end

  def test_persistence
    persistence = MASTER::Persistence.new('test.db')
    data = { test: 'data' }
    saved = persistence.save_session(data)
    loaded = persistence.load_session(saved['id'])
    assert_equal data, loaded
  end

  def test_large_file
    large = @code * 2000
    result = @engine.refactor(large)
    refute result[:success]
  end

  def test_offline
    ENV['OFFLINE'] = '1'
    result = @engine.refactor(@code)
    assert result[:success]
    ENV.delete 'OFFLINE'
  end
end
