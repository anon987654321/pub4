# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestUIColors < Minitest::Test
  def test_ui_module_exists
    assert defined?(MASTER::UI), "UI module should be defined"
  end

  def test_yellow_method_exists
    assert_respond_to MASTER::UI, :yellow
  end

  def test_green_method_exists
    assert_respond_to MASTER::UI, :green
  end

  def test_red_method_exists
    assert_respond_to MASTER::UI, :red
  end

  def test_cyan_method_exists
    assert_respond_to MASTER::UI, :cyan
  end

  def test_magenta_method_exists
    assert_respond_to MASTER::UI, :magenta
  end

  def test_blue_method_exists
    assert_respond_to MASTER::UI, :blue
  end

  def test_yellow_returns_string
    result = MASTER::UI.yellow("test")
    assert result.is_a?(String), "yellow should return a string"
  end

  def test_green_returns_string
    result = MASTER::UI.green("test")
    assert result.is_a?(String), "green should return a string"
  end

  def test_red_returns_string
    result = MASTER::UI.red("test")
    assert result.is_a?(String), "red should return a string"
  end

  def test_cyan_returns_string
    result = MASTER::UI.cyan("test")
    assert result.is_a?(String), "cyan should return a string"
  end

  def test_magenta_returns_string
    result = MASTER::UI.magenta("test")
    assert result.is_a?(String), "magenta should return a string"
  end

  def test_blue_returns_string
    result = MASTER::UI.blue("test")
    assert result.is_a?(String), "blue should return a string"
  end

  def test_colored_output_contains_input_text
    # Test that color methods preserve the input text in colored output
    text = "Hello World"

    assert MASTER::UI.yellow(text).include?("Hello World"), "yellow should contain input text"
    assert MASTER::UI.green(text).include?("Hello World"), "green should contain input text"
    assert MASTER::UI.red(text).include?("Hello World"), "red should contain input text"
    assert MASTER::UI.cyan(text).include?("Hello World"), "cyan should contain input text"
    assert MASTER::UI.magenta(text).include?("Hello World"), "magenta should contain input text"
    assert MASTER::UI.blue(text).include?("Hello World"), "blue should contain input text"
  end

  def test_existing_convenience_methods_still_work
    # Ensure we didn't break existing methods
    assert_respond_to MASTER::UI, :success
    assert_respond_to MASTER::UI, :error
    assert_respond_to MASTER::UI, :warn
    assert_respond_to MASTER::UI, :info
    assert_respond_to MASTER::UI, :dim
    assert_respond_to MASTER::UI, :bold
  end
end
