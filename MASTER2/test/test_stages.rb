# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestStages < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
  end

  def test_compress_with_string
    stage = MASTER::Stages::Compress.new
    result = stage.call("What is the meaning of life?")
    
    assert result.success?
    assert_equal :question, result.value![:intent]
    assert result.value![:text], "Should have compressed text"
  end

  def test_compress_with_hash
    stage = MASTER::Stages::Compress.new
    result = stage.call({ text: "Refactor this code" })
    
    assert result.success?
    assert_equal :refactor, result.value![:intent]
  end

  def test_compress_extracts_entities
    stage = MASTER::Stages::Compress.new
    result = stage.call("Check the pf firewall and httpd server")
    
    assert result.success?
    assert result.value![:entities][:services], "Should extract service names"
  end

  def test_compress_loads_axioms
    stage = MASTER::Stages::Compress.new
    result = stage.call({ text: "test" })
    
    assert result.success?
    assert result.value![:axioms], "Should load axioms"
    assert result.value![:axioms].length > 0, "Should have axioms loaded"
  end

  def test_debate_loads_members
    stage = MASTER::Stages::Debate.new
    result = stage.call({ text: "test proposal" })
    
    assert result.success?
    assert result.value![:council_responses], "Should have council responses"
    assert result.value![:consensus_reached], "Should reach consensus (stubbed)"
    assert result.value![:iterations_used], "Should track iterations used"
  end

  def test_debate_tracks_iterations
    stage = MASTER::Stages::Debate.new
    result = stage.call({ text: "test" })
    
    assert result.success?
    assert result.value![:iterations_used], "Should have iterations_used"
    assert result.value![:iterations_used] >= 1, "Should have at least 1 iteration"
  end

  def test_debate_single_round_when_consensus_reached
    stage = MASTER::Stages::Debate.new
    result = stage.call({ text: "safe proposal" })
    
    assert result.success?
    # With stub responses, consensus should be reached in 1 iteration
    assert_equal 1, result.value![:iterations_used], "Should complete in 1 iteration when consensus reached"
  end

  def test_debate_checks_threshold
    stage = MASTER::Stages::Debate.new
    result = stage.call({ text: "test" })
    
    assert result.success?
    assert result.value![:consensus_score], "Should calculate consensus score"
  end

  def test_lint_loads_axioms
    stage = MASTER::Stages::Lint.new
    result = stage.call({ text: "clean code" })
    
    assert result.success?
    assert result.value![:axioms_checked], "Should check axioms"
  end

  def test_admin_passthrough
    stage = MASTER::Stages::Admin.new
    result = stage.call({ text: "regular task", intent: :general })
    
    assert result.success?
    refute result.value![:admin_task], "Should not be admin task"
  end

  def test_admin_detects_admin
    stage = MASTER::Stages::Admin.new
    result = stage.call({ text: "configure pf firewall", intent: :admin })
    
    assert result.success?
    assert result.value![:admin_task], "Should detect admin task"
    assert_equal :pf, result.value![:task_type]
  end

  def test_render_typesetting
    stage = MASTER::Stages::Render.new
    result = stage.call({ text: 'Use "smart quotes" and -- em dashes...' })
    
    assert result.success?
    assert result.value![:rendered], "Should have rendered output"
    assert_match(/\u{201C}/, result.value![:rendered], "Should convert quotes")
    assert_match(/\u{2014}/, result.value![:rendered], "Should convert dashes")
    assert_match(/\u{2026}/, result.value![:rendered], "Should convert ellipses")
  end

  def test_render_preserves_code
    stage = MASTER::Stages::Render.new
    input = { text: "Here is code:\n```ruby\nx = \"test\"\n```\nDone." }
    result = stage.call(input)
    
    assert result.success?
    assert_match(/x = "test"/, result.value![:rendered], "Should preserve code")
  end

  def test_compress_loads_zsh_patterns_for_command_intent
    stage = MASTER::Stages::Compress.new
    result = stage.call("create a new script")
    
    assert result.success?
    assert result.value![:zsh_patterns], "Should load zsh patterns for command intent"
    assert result.value![:zsh_patterns].length > 0, "Should have zsh patterns loaded"
  end

  def test_compress_loads_zsh_patterns_for_admin_intent
    stage = MASTER::Stages::Compress.new
    result = stage.call("configure pf firewall")
    
    assert result.success?
    assert result.value![:zsh_patterns], "Should load zsh patterns for admin intent"
  end

  def test_compress_loads_zsh_patterns_for_services
    stage = MASTER::Stages::Compress.new
    result = stage.call("check httpd status")
    
    assert result.success?
    assert result.value![:zsh_patterns], "Should load zsh patterns when services detected"
  end

  def test_compress_no_zsh_patterns_for_general
    stage = MASTER::Stages::Compress.new
    result = stage.call("What is the weather?")
    
    assert result.success?
    refute result.value![:zsh_patterns], "Should not load zsh patterns for general intent"
  end

  def test_compress_loads_openbsd_patterns_for_command_intent
    stage = MASTER::Stages::Compress.new
    result = stage.call("create a new script")
    
    assert result.success?
    assert result.value![:openbsd_patterns], "Should load openbsd patterns for command intent"
    assert result.value![:openbsd_patterns].length > 0, "Should have openbsd patterns loaded"
  end

  def test_compress_loads_openbsd_patterns_for_admin_intent
    stage = MASTER::Stages::Compress.new
    result = stage.call("configure pf firewall")
    
    assert result.success?
    assert result.value![:openbsd_patterns], "Should load openbsd patterns for admin intent"
  end

  def test_compress_loads_openbsd_patterns_for_services
    stage = MASTER::Stages::Compress.new
    result = stage.call("check ntpd status")
    
    assert result.success?
    assert result.value![:openbsd_patterns], "Should load openbsd patterns when OpenBSD services detected"
  end

  def test_compress_extracts_openbsd_services
    stage = MASTER::Stages::Compress.new
    result = stage.call("restart ntpd and check sshd")
    
    assert result.success?
    assert result.value![:entities][:services], "Should extract OpenBSD service names"
    assert_includes result.value![:entities][:services], "ntpd"
    assert_includes result.value![:entities][:services], "sshd"
  end

  # Tests with LLM stubbing to avoid network requests
  def test_compress_classify_fallback_when_no_model
    stage = MASTER::Stages::Compress.new
    
    # Stub LLM.pick to return nil (no model available)
    MASTER::LLM.stub :pick, nil do
      result = stage.call("What is the meaning of life?")
      
      assert result.success?
      assert_equal :question, result.value![:intent], "Should use regex fallback when no model"
    end
  end

  def test_compress_classify_validates_llm_output
    stage = MASTER::Stages::Compress.new
    mock_response = Minitest::Mock.new
    mock_response.expect :content, "invalid_intent"
    mock_response.expect :respond_to?, false, [:tokens_in]
    
    mock_chat = Minitest::Mock.new
    mock_chat.expect :ask, mock_response, [String]
    
    # Stub LLM methods to return invalid intent
    MASTER::LLM.stub :pick, "test-model" do
      MASTER::LLM.stub :chat, mock_chat, [{ model: "test-model" }] do
        result = stage.call("test input")
        
        assert result.success?
        assert_equal :general, result.value![:intent], "Should fallback to :general for invalid intent"
      end
    end
    
    mock_chat.verify
    mock_response.verify
  end

  def test_compress_extract_handles_invalid_json
    stage = MASTER::Stages::Compress.new
    mock_response = Minitest::Mock.new
    mock_response.expect :content, "not valid json"
    mock_response.expect :respond_to?, false, [:tokens_in]
    
    mock_chat = Minitest::Mock.new
    mock_chat.expect :ask, mock_response, [String]
    
    # Stub LLM methods to return invalid JSON
    MASTER::LLM.stub :pick, "test-model" do
      MASTER::LLM.stub :chat, mock_chat, [{ model: "test-model" }] do
        result = stage.call("test input")
        
        assert result.success?
        # Should use regex fallback when JSON parsing fails
        assert result.value![:entities].is_a?(Hash)
      end
    end
    
    mock_chat.verify
    mock_response.verify
  end

  def test_compress_extract_validates_json_structure
    stage = MASTER::Stages::Compress.new
    mock_response = Minitest::Mock.new
    # Return JSON with non-array values
    mock_response.expect :content, '{"files": "not-an-array", "services": [123], "configs": []}'
    mock_response.expect :respond_to?, false, [:tokens_in]
    
    mock_chat = Minitest::Mock.new
    mock_chat.expect :ask, mock_response, [String]
    
    MASTER::LLM.stub :pick, "test-model" do
      MASTER::LLM.stub :chat, mock_chat, [{ model: "test-model" }] do
        result = stage.call("test.rb config.yml")
        
        assert result.success?
        entities = result.value![:entities]
        # Should only include valid arrays
        refute entities.key?(:files), "Should not include non-array values"
        refute entities.key?(:services), "Should not include array with non-string elements"
        assert entities[:configs].is_a?(Array), "Should include valid array"
      end
    end
    
    mock_chat.verify
    mock_response.verify
  end

  def test_compress_classify_logs_cost_when_available
    stage = MASTER::Stages::Compress.new
    mock_response = Minitest::Mock.new
    mock_response.expect :content, "question"
    mock_response.expect :respond_to?, true, [:tokens_in]
    mock_response.expect :respond_to?, true, [:tokens_out]
    mock_response.expect :tokens_in, 10
    mock_response.expect :tokens_out, 5
    
    mock_chat = Minitest::Mock.new
    mock_chat.expect :ask, mock_response, [String]
    
    cost_logged = false
    
    MASTER::LLM.stub :pick, "test-model" do
      MASTER::LLM.stub :chat, mock_chat, [{ model: "test-model" }] do
        MASTER::LLM.stub :log_cost, ->(model:, tokens_in:, tokens_out:) {
          cost_logged = true
          assert_equal "test-model", model
          assert_equal 10, tokens_in
          assert_equal 5, tokens_out
        } do
          result = stage.call("What is this?")
          
          assert result.success?
          assert cost_logged, "Should log cost when token info available"
        end
      end
    end
    
    mock_chat.verify
    mock_response.verify
  end
end
