#!/usr/bin/env ruby
# frozen_string_literal: true

# MASTER v50.8 Test Suite

require_relative '../lib/master'

class TestRunner
  def initialize
    @passed = 0
    @failed = 0
  end

  def assert(name, condition)
    if condition
      @passed += 1
      puts "  ok: #{name}"
    else
      @failed += 1
      puts "  FAIL: #{name}"
    end
  end

  def run
    puts "master #{MASTER::VERSION} tests"
    puts

    test_modules
    test_paths
    test_result
    test_principles
    test_personas
    test_llm
    test_boot

    puts
    puts "#{@passed} passed, #{@failed} failed"
    exit(@failed > 0 ? 1 : 0)
  end

  def test_modules
    puts "modules:"
    assert "MASTER defined", defined?(MASTER)
    assert "VERSION exists", MASTER::VERSION =~ /\d+\.\d+/
    assert "ROOT exists", MASTER::ROOT.is_a?(String)
  end

  def test_paths
    puts "paths:"
    assert "Paths.root", MASTER::Paths.root.is_a?(String)
    assert "Paths.lib", MASTER::Paths.lib.end_with?('lib')
    assert "Paths.principles", MASTER::Paths.principles.include?('principles')
  end

  def test_result
    puts "result:"
    ok = MASTER::Result.ok(42)
    err = MASTER::Result.err("fail")
    assert "Result.ok", ok.ok? && ok.value == 42
    assert "Result.err", err.err? && err.error == "fail"
  end

  def test_principles
    puts "principles:"
    principles = MASTER::Principle.load_all
    assert "loads principles", principles.is_a?(Array)
    assert "has principles", principles.size > 0
    assert "principle has name", principles.first&.dig(:name)
  end

  def test_personas
    puts "personas:"
    personas = MASTER::Persona.load_all
    assert "loads personas", personas.is_a?(Array)
  end

  def test_llm
    puts "llm:"
    assert "TIERS defined", MASTER::LLM::TIERS.is_a?(Hash)
    assert "has 5 tiers", MASTER::LLM::TIERS.size == 5
    assert "has fast tier", MASTER::LLM::TIERS[:fast]
  end

  def test_boot
    puts "boot:"
    # Suppress output
    old_stdout = $stdout
    $stdout = StringIO.new
    principles = MASTER::Boot.run(verbose: false)
    $stdout = old_stdout
    assert "boot returns principles", principles.is_a?(Array)
  end
end

TestRunner.new.run
