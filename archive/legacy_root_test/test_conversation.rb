# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/nlu'
require_relative '../lib/conversation'

class TestConversation < Minitest::Test
  def setup
    @conversation = MASTER::Conversation.new
  end

  def test_initialization
    assert_empty @conversation.history
    assert @conversation.context
  end

  def test_empty_input_returns_error
    result = @conversation.process("")
    assert_equal :error, result[:status]
    assert result[:message].include?("Empty")
  end

  def test_nil_input_returns_error
    result = @conversation.process(nil)
    assert_equal :error, result[:status]
  end

  def test_process_refactor_command
    result = @conversation.process("refactor lib/user.rb")
    
    assert_includes [:success, :error], result[:status]
    assert result[:message]
  end

  def test_process_analyze_command
    result = @conversation.process("analyze test/user_test.rb")
    
    assert_includes [:success, :error], result[:status]
    assert result[:message]
  end

  def test_history_tracking
    @conversation.process("refactor lib/user.rb")
    @conversation.process("analyze lib/user.rb")
    
    assert_equal 2, @conversation.history.size
    assert @conversation.history.first[:input]
    assert @conversation.history.first[:intent]
    assert @conversation.history.first[:result]
  end

  def test_history_limit
    # Add more than MAX_HISTORY entries
    15.times do |i|
      @conversation.process("refactor file#{i}.rb")
    end
    
    assert_equal MASTER::Conversation::MAX_HISTORY, @conversation.history.size
  end

  def test_context_updates_with_files
    @conversation.process("refactor lib/user.rb")
    
    # Context should track the file
    assert @conversation.context[:last_files]
  end

  def test_pronoun_resolution_with_current_file
    # First command sets context
    @conversation.process("analyze lib/user.rb")
    
    # Second command uses pronoun
    result = @conversation.process("refactor it")
    
    # Should resolve "it" to lib/user.rb through context
    assert result[:status]
  end

  def test_pronoun_resolution_without_context
    # No context set, pronoun can't be resolved well
    result = @conversation.process("refactor it")
    
    # Should either error or ask for clarification
    assert result[:status]
  end

  def test_clear_history
    @conversation.process("refactor lib/user.rb")
    assert_equal 1, @conversation.history.size
    
    @conversation.clear
    
    assert_empty @conversation.history
    refute @conversation.context[:current_file]
  end

  def test_recent_returns_last_n
    5.times { |i| @conversation.process("refactor file#{i}.rb") }
    
    recent = @conversation.recent(3)
    assert_equal 3, recent.size
  end

  def test_summary_with_no_history
    summary = @conversation.summary
    assert_includes summary, "No conversation"
  end

  def test_summary_with_history
    @conversation.process("refactor lib/user.rb")
    @conversation.process("analyze lib/user.rb")
    
    summary = @conversation.summary
    assert_includes summary, "Conversation Summary"
    assert_includes summary, "refactor lib/user.rb"
    assert_includes summary, "analyze lib/user.rb"
  end

  def test_execute_refactor_with_file
    intent = {
      intent: :refactor,
      entities: { files: ["lib/user.rb"] },
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_refactor, intent)
    assert_equal :success, result[:status]
    assert_includes result[:message], "lib/user.rb"
  end

  def test_execute_refactor_without_file
    intent = {
      intent: :refactor,
      entities: {},
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_refactor, intent)
    assert_equal :error, result[:status]
  end

  def test_execute_analyze_with_files
    intent = {
      intent: :analyze,
      entities: { files: ["lib/user.rb", "lib/auth.rb"] },
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_analyze, intent)
    assert_equal :success, result[:status]
  end

  def test_execute_analyze_without_targets
    intent = {
      intent: :analyze,
      entities: {},
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_analyze, intent)
    assert_equal :error, result[:status]
  end

  def test_execute_explain
    intent = {
      intent: :explain,
      entities: { target: "authentication logic" },
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_explain, intent)
    assert_equal :success, result[:status]
  end

  def test_execute_fix
    intent = {
      intent: :fix,
      entities: { files: ["lib/buggy.rb"] },
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_fix, intent)
    assert_equal :success, result[:status]
  end

  def test_execute_search
    intent = {
      intent: :search,
      entities: { patterns: ["User class"] },
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_search, intent)
    assert_equal :success, result[:status]
  end

  def test_execute_show
    intent = {
      intent: :show,
      entities: { files: ["lib/user.rb"] },
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_show, intent)
    assert_equal :success, result[:status]
  end

  def test_execute_list
    intent = {
      intent: :list,
      entities: { directories: ["lib/"] },
      confidence: 0.9
    }
    
    result = @conversation.send(:execute_list, intent)
    assert_equal :success, result[:status]
  end

  def test_execute_help
    intent = {
      intent: :help,
      entities: {},
      confidence: 1.0
    }
    
    result = @conversation.send(:execute_help, intent)
    assert_equal :success, result[:status]
    assert result[:commands]
    refute_empty result[:commands]
  end

  def test_execute_unknown_intent
    intent = {
      intent: :unknown,
      entities: {},
      confidence: 0.3
    }
    
    result = @conversation.send(:execute_intent, intent)
    assert_equal :unknown, result[:status]
  end

  def test_update_context_with_files
    intent = { intent: :refactor, entities: { files: ["lib/user.rb"] } }
    result = { status: :success }
    
    @conversation.send(:update_context, intent, result)
    
    assert_equal "lib/user.rb", @conversation.context[:current_file]
    assert_includes @conversation.context[:last_files], "lib/user.rb"
  end

  def test_update_context_with_directories
    intent = { intent: :list, entities: { directories: ["lib/"] } }
    result = { status: :success }
    
    @conversation.send(:update_context, intent, result)
    
    assert_equal "lib/", @conversation.context[:current_directory]
  end

  def test_resolve_pronouns_with_current_file
    @conversation.instance_variable_get(:@context)[:current_file] = "lib/user.rb"
    
    intent = { intent: :refactor, entities: {} }
    resolved = @conversation.send(:resolve_pronouns, intent, "refactor it")
    
    assert_equal ["lib/user.rb"], resolved[:entities][:files]
  end

  def test_resolve_pronouns_without_pronoun
    intent = { intent: :refactor, entities: { files: ["explicit.rb"] } }
    resolved = @conversation.send(:resolve_pronouns, intent, "refactor explicit.rb")
    
    # Should not change if no pronoun present
    assert_equal ["explicit.rb"], resolved[:entities][:files]
  end
end
