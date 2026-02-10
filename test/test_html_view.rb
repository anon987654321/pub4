require 'minitest/autorun'

# Stub the MASTER module for testing
module MASTER
  def self.root
    File.expand_path('../..', __FILE__)
  end
end

require_relative '../lib/html_view'

class TestHTMLView < Minitest::Test
  def setup
    @view = MASTER::HTMLView.new
  end

  def test_initialization
    assert_equal 'dark', @view.instance_variable_get(:@theme)
    
    light_view = MASTER::HTMLView.new(theme: 'light')
    assert_equal 'light', light_view.instance_variable_get(:@theme)
  end

  def test_collect_metrics
    metrics = @view.collect_metrics('lib/')
    
    assert_kind_of Hash, metrics
    assert metrics.key?(:total_files)
    assert metrics.key?(:total_lines)
    assert metrics.key?(:score)
    assert metrics.key?(:violations)
    assert metrics.key?(:suggestions)
  end

  def test_detect_violations
    violations = @view.detect_violations('lib/')
    
    assert_kind_of Array, violations
    # May or may not have violations depending on codebase
  end

  def test_generate_dashboard
    html = @view.generate_dashboard('lib/')
    
    assert_kind_of String, html
    assert html.include?('MASTER')
    assert html.include?('html')
    assert html.include?('Code Quality')
  end

  def test_render_erb
    template = "Hello <%= name %>"
    data = { name: "World" }
    
    result = @view.send(:render_erb, template, data)
    assert_equal "Hello World", result
  end

  def test_render_erb_escapes_keys
    template = "Value: <%= test_key %>"
    data = { test_key: "123" }
    
    result = @view.send(:render_erb, template, data)
    assert_equal "Value: 123", result
  end
end
