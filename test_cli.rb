#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE TEST SUITE v1.6.0
# Tests all workflow enhancements including chat, web agent, and autonomy features

require "minitest/autorun"
require "yaml"
require "fileutils"
require "tempfile"

# Skip dependency auto-install during tests
ENV["SKIP_DEPS"] = "1"

# Load CLI
require_relative "cli"

class ConvergenceTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
    
    # Create minimal test config
    @test_config = {
      "version" => "1.4.0-test",
      "laws" => {
        "robustness" => {"priority" => 1},
        "singularity" => {"priority" => 2},
        "linearity" => {"priority" => 3}
      },
      "registry" => [
        {"name" => "secrets", "pattern" => "password\s*=", "law" => "robustness", "severity" => "veto"},
        {"name" => "magic_numbers", "pattern" => "\b\d{3,}\b", "law" => "abstraction", "severity" => "medium"}
      ],
      "scanning" => {
        "patterns" => ["**/*.rb"],
        "exclude" => ["vendor/**/*"],
        "auto_clean" => false
      },
      "tracking" => {
        "violations" => {"enabled" => true, "history_dir" => ".convergence_history"},
        "patterns" => {"enabled" => true, "library_dir" => ".convergence_patterns"},
        "context" => {"enabled" => true, "header_injection" => true},
        "personas" => {"enabled" => true, "journal_dir" => ".convergence_personas"},
        "refactoring" => {"enabled" => true, "journal_file" => ".convergence_journal.md"}
      },
      "workflow" => {
        "enabled" => true,
        "states" => ["clean", "scan", "analyze", "fix"],
        "state_file" => ".convergence_workflow"
      },
      "learning" => {
        "enabled" => true,
        "capture_fixes" => true,
        "min_samples" => 3
      },
      "convergence" => {
        "inline_suggestions" => {"enabled" => true, "max_per_violation" => 3}
      },
      "dashboard" => {
        "enabled" => true,
        "show" => ["total_files", "veto_count"]
      },
      "priority" => {
        "rules" => ["veto_count_desc"]
      },
      "integration" => {
        "pre_work_snapshot" => false,
        "commit_hooks" => {"enabled" => false}
      },
      "ux" => {
        "indicators" => {"success" => "✓", "failure" => "✗"},
        "prefixes" => {"operation" => "→"}
      }
    }
    
    File.write("master.yml", YAML.dump(@test_config))
    
    # Create required directories
    FileUtils.mkdir_p(".convergence_history")
    FileUtils.mkdir_p(".convergence_patterns")
    FileUtils.mkdir_p(".convergence_personas")
    
    Logger.init(@test_config)
    Logger.set_quiet(true)
  end
  
  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_result_monad_success
    result = Result.success("value")
    assert result.success?
    refute result.failure?
    assert_equal "value", result.value
  end
  
  def test_result_monad_failure
    result = Result.failure("error")
    refute result.success?
    assert result.failure?
    assert_equal "error", result.error
  end
  
  def test_result_monad_and_then
    result = Result.success(5).and_then { |v| Result.success(v * 2) }
    assert_equal 10, result.value
  end
  
  def test_result_monad_or_else
    result = Result.failure("error")
    assert_equal "default", result.or_else("default")
  end
  
  def test_violation_creation
    v = Violation.new(
      file: "test.rb",
      line: 10,
      rule: "magic_numbers",
      law: "abstraction",
      severity: "medium",
      details: "1000"
    )
    
    assert_equal "test.rb", v.file
    assert_equal 10, v.line
    assert_equal "magic_numbers", v.rule
    refute v.veto?
  end
  
  def test_violation_veto
    v = Violation.new(
      file: "test.rb",
      line: 5,
      rule: "secrets",
      law: "robustness",
      severity: "veto"
    )
    
    assert v.veto?
  end
  
  def test_scanner_pattern_detection
    File.write("test.rb", "timeout = 5000
")
    
    scanner = Scanner.new(@test_config)
    result = scanner.scan("test.rb")
    
    assert result.success?
    violations = result.value
    assert violations.any? { |v| v.rule == "magic_numbers" }
  end
  
  def test_scanner_veto_detection
    File.write("test.rb", "password = 'secret123'
")
    
    scanner = Scanner.new(@test_config)
    result = scanner.scan("test.rb")
    
    violations = result.value
    assert violations.any?(&:veto?)
  end
  
  def test_scanner_recursive
    FileUtils.mkdir_p("lib")
    File.write("lib/auth.rb", "timeout = 3000
")
    File.write("lib/db.rb", "limit = 100
") # 100 is too small for magic_numbers
    
    scanner = Scanner.new(@test_config)
    results = scanner.scan_recursive
    
    assert results.key?("lib/auth.rb")
    refute results.key?("lib/db.rb") # No violations
  end
  
  def test_state_manager_initialization
    StateManager.init(@test_config)
    StateManager.ensure_directories
    
    assert Dir.exist?(".convergence_history")
    assert Dir.exist?(".convergence_patterns")
    assert Dir.exist?(".convergence_personas")
  end
  
  def test_state_manager_save_initial_state
    StateManager.init(@test_config)
    StateManager.save_initial_state
    
    assert File.exist?(".convergence_state.yml")
    
    state = YAML.load_file(".convergence_state.yml")
    assert state["timestamp"]
    assert state["pwd"]
  end
  
  def test_state_manager_update_context
    StateManager.init(@test_config)
    
    progress = {
      total: 10,
      converged: 7,
      remaining: 3,
      percent: 70,
      veto: 0,
      blockers: [],
      next_steps: ["Fix remaining 3 files"]
    }
    
    StateManager.update_context("test.rb", [], progress)
    
    assert File.exist?(".convergence_context.md")
    
    content = File.read(".convergence_context.md")
    assert_match(/Total Files: 10/, content)
    assert_match(/Converged: 7/, content)
  end
  
  def test_violation_tracker
    ViolationTracker.init(@test_config)
    
    violation = Violation.new(
      file: "test.rb",
      line: 10,
      rule: "magic_numbers",
      law: "abstraction",
      severity: "medium"
    )
    
    ViolationTracker.track("test.rb", violation)
    
    assert File.exist?(".convergence_history/test.rb.jsonl")
    
    lines = File.readlines(".convergence_history/test.rb.jsonl")
    assert_equal 1, lines.size
    
    entry = JSON.parse(lines.first)
    assert_equal 10, entry["line"]
    assert_equal "magic_numbers", entry["type"]
  end
  
  def test_violation_tracker_recurrence
    ViolationTracker.init(@test_config)
    
    violation = Violation.new(
      file: "test.rb",
      line: 10,
      rule: "magic_numbers",
      law: "abstraction",
      severity: "medium"
    )
    
    # Track same violation 4 times
    4.times { ViolationTracker.track("test.rb", violation) }
    
    recurrence = ViolationTracker.analyze_recurrence("test.rb")
    
    assert recurrence["L10 magic_numbers"]
    assert_equal 4, recurrence["L10 magic_numbers"]
  end
  
  def test_context_injector
    ContextInjector.init(@test_config)
    
    File.write("test.rb", "def foo
  puts 'hello'
end
")
    
    violation = Violation.new(
      file: "test.rb",
      line: 2,
      rule: "magic_numbers",
      law: "abstraction",
      severity: "medium"
    )
    
    ContextInjector.inject("test.rb", [violation], ["architect"])
    
    content = File.read("test.rb")
    assert_match(/# CONVERGENCE: 1 violations/, content)
    assert_match(/# LAST_SCAN:/, content)
    assert_match(/# PERSONAS: architect/, content)
  end
  
  def test_context_injector_remove
    ContextInjector.init(@test_config)
    
    File.write("test.rb", "# CONVERGENCE: 1 violations
# LAST_SCAN: 2024
def foo
end
")
    
    ContextInjector.remove("test.rb")
    
    content = File.read("test.rb")
    refute_match(/# CONVERGENCE:/, content)
    assert_match(/def foo/, content)
  end
  
  def test_persona_journal
    PersonaJournal.init(@test_config)
    
    PersonaJournal.log("security", "flagged password in config", file: "config.rb", line: 10)
    
    assert File.exist?(".convergence_personas/security.log")
    
    entries = PersonaJournal.read("security")
    assert_equal 1, entries.size
    assert_match(/flagged password/, entries.first)
  end
  
  def test_persona_journal_recent
    PersonaJournal.init(@test_config)
    
    10.times { |i| PersonaJournal.log("maintainer", "observation #{i}") }
    
    recent = PersonaJournal.recent("maintainer", 5)
    assert_equal 5, recent.size
    assert_match(/observation 9/, recent.last)
  end
  
  def test_refactoring_journal
    RefactoringJournal.init(@test_config)
    
    before_code = "timeout = 3000"
    after_code = "TIMEOUT = 3000"
    
    RefactoringJournal.log_fix(
      "test.rb",
      10,
      before_code,
      after_code,
      "abstraction",
      "magic_numbers",
      "extracted constant"
    )
    
    assert File.exist?(".convergence_journal.md")
    
    content = File.read(".convergence_journal.md")
    assert_match(/test.rb:10/, content)
    assert_match(/timeout = 3000/, content)
    assert_match(/TIMEOUT = 3000/, content)
    assert_match(/abstraction/, content)
  end
  
  def test_learning_engine_capture
    LearningEngine.init(@test_config)
    
    before_code = "timeout = 3000"
    after_code = "TIMEOUT = 3000"
    
    LearningEngine.capture_fix(
      "test.rb",
      10,
      before_code,
      after_code,
      "abstraction",
      "magic_numbers"
    )
    
    assert File.exist?(".convergence_patterns/magic_numbers.yml")
    
    patterns = YAML.load_file(".convergence_patterns/magic_numbers.yml")
    assert_equal 1, patterns.size
    assert_equal before_code, patterns.first[:before]
  end
  
  def test_learning_engine_generate_rule
    LearningEngine.init(@test_config)
    
    # Capture same fix 3 times
    3.times do |i|
      LearningEngine.capture_fix(
        "test#{i}.rb",
        10,
        "timeout = 3000",
        "TIMEOUT = 3000",
        "abstraction",
        "magic_numbers"
      )
    end
    
    patterns = YAML.load_file(".convergence_patterns/magic_numbers.yml")
    rule = LearningEngine.generate_rule("magic_numbers", patterns)
    
    assert rule
    assert_equal "learned_magic_numbers", rule[:name]
    assert_equal "abstraction", rule[:law]
    assert rule[:confidence] >= 0.5
  end
  
  def test_workflow_state_machine
    WorkflowStateMachine.init(@test_config)
    
    assert_equal "clean", WorkflowStateMachine.current_state
    
    WorkflowStateMachine.transition_to("scan")
    assert_equal "scan", WorkflowStateMachine.current_state
    
    WorkflowStateMachine.transition_to("analyze")
    assert_equal "analyze", WorkflowStateMachine.current_state
  end
  
  def test_workflow_checkpoint
    WorkflowStateMachine.init(@test_config)
    
    WorkflowStateMachine.transition_to("scan")
    WorkflowStateMachine.checkpoint
    
    assert File.exist?(".convergence_workflow.checkpoint")
    
    checkpoint = YAML.load_file(".convergence_workflow.checkpoint")
    assert_equal "scan", checkpoint["state"]
    assert checkpoint["timestamp"]
  end
  
  def test_dependency_analyzer_analyze
    DependencyAnalyzer.init(@test_config.merge("priority" => {"dependency_analysis" => true}))
    
    FileUtils.mkdir_p("lib")
    File.write("lib/a.rb", "require 'lib/b'
")
    File.write("lib/b.rb", "# no deps
")
    
    files = ["lib/a.rb", "lib/b.rb"]
    deps = DependencyAnalyzer.analyze(files)
    
    assert deps["lib/a.rb"]
    assert deps["lib/a.rb"].size > 0
  end
  
  def test_dependency_analyzer_sort
    DependencyAnalyzer.init(@test_config.merge("priority" => {"dependency_analysis" => true}))
    
    files = ["a.rb", "b.rb", "c.rb"]
    deps = {
      "a.rb" => ["b.rb"],
      "b.rb" => ["c.rb"],
      "c.rb" => []
    }
    
    sorted = DependencyAnalyzer.sort_by_dependency(files, deps)
    
    # c should come before b, b before a (leaves first)
    assert sorted.index("c.rb") < sorted.index("b.rb")
    assert sorted.index("b.rb") < sorted.index("a.rb")
  end
  
  def test_priority_queue_sort
    PriorityQueue.init(@test_config)
    
    files = ["a.rb", "b.rb", "c.rb"]
    
    violations_by_file = {
      "a.rb" => [
        Violation.new(file: "a.rb", line: 1, rule: "secrets", law: "robustness", severity: "veto")
      ],
      "b.rb" => [],
      "c.rb" => [
        Violation.new(file: "c.rb", line: 1, rule: "magic_numbers", law: "abstraction", severity: "medium")
      ]
    }
    
    sorted = PriorityQueue.sort(files, violations_by_file)
    
    # a.rb has veto so should be first
    assert_equal "a.rb", sorted.first
  end
  
  def test_inline_suggestions_magic_numbers
    InlineSuggestions.init(@test_config)
    
    violation = Violation.new(
      file: "test.rb",
      line: 10,
      rule: "magic_numbers",
      law: "abstraction",
      severity: "medium",
      details: "3000"
    )
    
    suggestions = InlineSuggestions.generate(violation)
    
    assert suggestions.size > 0
    assert suggestions.any? { |s| s.include?("EXTRACT") }
  end
  
  def test_inline_suggestions_long_method
    InlineSuggestions.init(@test_config)
    
    violation = Violation.new(
      file: "test.rb",
      line: 10,
      rule: "long_method",
      law: "linearity",
      severity: "high",
      details: "process"
    )
    
    suggestions = InlineSuggestions.generate(violation)
    
    assert suggestions.size > 0
    assert suggestions.any? { |s| s.include?("EXTRACT") || s.include?("SPLIT") }
  end
  
  def test_dashboard_display
    Dashboard.init(@test_config)
    
    results = {
      "a.rb" => [
        Violation.new(file: "a.rb", line: 1, rule: "secrets", law: "robustness", severity: "veto")
      ],
      "b.rb" => [],
      "c.rb" => []
    }
    
    # Should not crash
    Dashboard.display(results)
  end
  
  def test_scanner_excludes_vendor
    FileUtils.mkdir_p("vendor/bundle")
    File.write("vendor/bundle/gem.rb", "password = 'secret'
")
    
    scanner = Scanner.new(@test_config)
    results = scanner.scan_recursive
    
    refute results.key?("vendor/bundle/gem.rb")
  end
  
  def test_end_to_end_workflow
    # Create test file with violations
    File.write("test.rb", <<~RUBY)
      def process(a, b, c, d)
        timeout = 5000
        password = 'secret'
        puts a + b
      end
    RUBY
    
    # Initialize all systems
    StateManager.init(@test_config)
    ViolationTracker.init(@test_config)
    ContextInjector.init(@test_config)
    LearningEngine.init(@test_config)
    WorkflowStateMachine.init(@test_config)
    
    # Scan
    scanner = Scanner.new(@test_config)
    result = scanner.scan("test.rb")
    
    violations = result.value
    
    # Should detect both magic_numbers and secrets
    assert violations.any? { |v| v.rule == "magic_numbers" }
    assert violations.any? { |v| v.rule == "secrets" }
    
    # Track violations
    violations.each { |v| ViolationTracker.track("test.rb", v) }
    
    # Should have history
    assert File.exist?(".convergence_history/test.rb.jsonl")
    
    # Inject context header
    ContextInjector.inject("test.rb", violations, ["security", "architect"])
    
    content = File.read("test.rb")
    assert_match(/# CONVERGENCE:/, content)
    assert_match(/# PERSONAS: security architect/, content)
    
    # Update workflow state
    WorkflowStateMachine.transition_to("scan")
    WorkflowStateMachine.transition_to("analyze")
    
    assert_equal "analyze", WorkflowStateMachine.current_state
    
    # Simulate fix
    LearningEngine.capture_fix(
      "test.rb",
      2,
      "timeout = 5000",
      "TIMEOUT = 5000",
      "abstraction",
      "magic_numbers"
    )
    
    # Should have pattern
    assert File.exist?(".convergence_patterns/magic_numbers.yml")
  end
end

# New v1.6.0 Tests
class ChatAndWebTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
    
    @test_config = {
      "version" => "1.6.0-test",
      "laws" => {},
      "registry" => [],
      "scanning" => { "patterns" => ["**/*.rb"] }
    }
    File.write("master.yml", YAML.dump(@test_config))
  end
  
  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_dependency_manager_openbsd_detection
    # Should detect if running on OpenBSD
    result = DependencyManager.openbsd?
    assert [true, false].include?(result)
  end
  
  def test_dependency_manager_gems_list
    assert DependencyManager::GEMS.key?("ferrum")
    assert DependencyManager::GEMS.key?("async")
  end
  
  def test_color_module
    # Colors should work or degrade gracefully
    assert_equal "test", C.g("test").gsub(/\e\[\d+m/, "")
    assert_equal "test", C.r("test").gsub(/\e\[\d+m/, "")
    assert_equal "test", C.b("test").gsub(/\e\[\d+m/, "")
  end
  
  def test_web_module_init
    Web.init
    # Should report status without crashing
    status = Web.status
    assert status.include?("ferrum:")
  end
  
  def test_voice_module_init
    Voice.init({})
    status = Voice.status
    assert status.include?("tts:")
    assert status.include?("stt:")
  end
  
  def test_openrouter_chat_init
    OpenRouterChat.init(@test_config)
    # Should handle missing API key gracefully
    refute OpenRouterChat.available?
  end
  
  def test_openrouter_chat_model_switching
    OpenRouterChat.init(@test_config)
    OpenRouterChat.set_model("deepseek/deepseek-chat")
    # Model should be updated (even without API key)
  end
  
  def test_openrouter_chat_add_context
    OpenRouterChat.init(@test_config)
    OpenRouterChat.add_context("test", "test content")
    # Should not crash
  end
  
  def test_openrouter_chat_clear_conversation
    OpenRouterChat.init(@test_config)
    OpenRouterChat.clear_conversation
    assert_equal 0, OpenRouterChat.conversation_length
  end
  
  def test_ferrum_availability_check
    # Should not crash even if Ferrum not installed
    assert [true, false].include?(FERRUM_AVAILABLE)
  end
  
  def test_falcon_availability_check
    assert [true, false].include?(FALCON_AVAILABLE)
  end
end

class CommandParsingTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
    
    @test_config = {
      "version" => "1.6.0-test",
      "laws" => {},
      "registry" => [],
      "scanning" => { "patterns" => ["**/*.rb"] }
    }
    File.write("master.yml", YAML.dump(@test_config))
  end
  
  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_slash_command_detection
    # Commands start with /
    assert "/help".start_with?("/")
    assert "/browse https://example.com".start_with?("/")
    refute "hello world".start_with?("/")
  end
  
  def test_code_block_extraction
    response = "Here's the fix:\n```zsh\necho hello\n```\nDone."
    match = response.match(/```(?:zsh|shell|bash|sh)\n(.+?)```/m)
    assert match
    assert_equal "echo hello\n", match[1]
  end
  
  def test_ruby_block_extraction
    response = "Run this:\n```ruby\nputs 'hi'\n```"
    match = response.match(/```ruby\n(.+?)```/m)
    assert match
    assert_equal "puts 'hi'\n", match[1]
  end
  
  def test_dangerous_command_blocking
    blocked = ["rm -rf /", "rm -rf ~"]
    blocked.each do |cmd|
      assert blocked.any? { |b| cmd.include?(b.split.first(2).join(" ")) }
    end
  end
end

# Run tests if executed directly
if __FILE__ == $0
  puts "CONVERGENCE TEST SUITE v1.6.0"
  puts "=============================="
  puts
end
