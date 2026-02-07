# frozen_string_literal: true

require_relative "test_helper"

class TestRefactor < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @test_file = File.join(@test_dir, "sample.rb")
    @original_content = <<~RUBY
      # frozen_string_literal: true
      
      class Calculator
        def add(a, b)
          a + b
        end
        
        def subtract(a, b)
          a - b
        end
      end
    RUBY
    
    File.write(@test_file, @original_content)
    MASTER::Undo.clear
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    MASTER::Undo.clear
  end

  def test_refactor_missing_file
    result = MASTER::Commands.send(:refactor, "nonexistent.rb")
    assert result.err?
    assert_match /File not found/, result.error
  end

  def test_refactor_no_arguments
    result = MASTER::Commands.send(:refactor, nil)
    assert result.err?
    assert_match /Usage/, result.error
  end

  def test_extract_mode_preview_default
    mode = MASTER::Commands.send(:extract_mode, [])
    assert_equal :preview, mode
  end

  def test_extract_mode_preview_explicit
    mode = MASTER::Commands.send(:extract_mode, ["--preview"])
    assert_equal :preview, mode
  end

  def test_extract_mode_raw
    mode = MASTER::Commands.send(:extract_mode, ["--raw"])
    assert_equal :raw, mode
  end

  def test_extract_mode_apply
    mode = MASTER::Commands.send(:extract_mode, ["--apply"])
    assert_equal :apply, mode
  end

  def test_lint_output_returns_text
    text = "Sample output"
    result = MASTER::Commands.send(:lint_output, text)
    assert_equal text, result
  end

  def test_render_output_returns_text
    text = "Sample output"
    result = MASTER::Commands.send(:render_output, text)
    # Should return text, possibly with typography applied
    refute_nil result
  end

  def test_format_council_summary_with_veto
    council_info = { vetoed_by: ["Security Guard", "Style Guide"] }
    summary = MASTER::Commands.send(:format_council_summary, council_info)
    assert_match /VETOED/, summary
    assert_match /Security Guard/, summary
  end

  def test_format_council_summary_with_consensus
    council_info = { consensus: 0.85, verdict: :approved }
    summary = MASTER::Commands.send(:format_council_summary, council_info)
    assert_match /APPROVED/, summary
    assert_match /85%/, summary
  end

  def test_format_council_summary_nil
    summary = MASTER::Commands.send(:format_council_summary, nil)
    assert_nil summary
  end

  def test_undo_tracks_edit
    modified_content = @original_content.gsub("add", "plus")
    
    # Track the edit
    MASTER::Undo.track_edit(@test_file, @original_content)
    File.write(@test_file, modified_content)
    
    # Verify file was modified
    assert_equal modified_content, File.read(@test_file)
    
    # Undo should restore original
    MASTER::Undo.undo
    assert_equal @original_content, File.read(@test_file)
  end

  def test_undo_history_shows_edit
    MASTER::Undo.track_edit(@test_file, @original_content)
    history = MASTER::Undo.history
    
    assert_equal 1, history.size
    assert_match /Edit/, history.first
    assert_match /sample\.rb/, history.first
  end

  # Integration test with mocked Chamber
  def test_refactor_preview_mode_with_mock
    # Mock Chamber to return a simple change
    modified = @original_content.gsub("add", "plus")
    
    mock_chamber = Minitest::Mock.new
    mock_result = MASTER::Result.ok({
      final: modified,
      proposals: [{ model: :test, proposal: modified }],
      council: { consensus: 0.9, verdict: :approved },
      cost: 0.01,
      rounds: 1
    })
    
    mock_chamber.expect(:deliberate, mock_result, [String, Hash])
    
    MASTER::Chamber.stub :new, mock_chamber do
      # Capture output
      output = capture_io do
        MASTER::Commands.send(:refactor, @test_file)
      end.join
      
      # Should show diff in preview mode
      assert_match /---/, output
      assert_match /\+\+\+/, output
      assert_match /Proposals/, output
    end
    
    mock_chamber.verify
  end

  def test_refactor_raw_mode_with_mock
    modified = @original_content.gsub("add", "plus")
    
    mock_chamber = Minitest::Mock.new
    mock_result = MASTER::Result.ok({
      final: modified,
      proposals: [{ model: :test, proposal: modified }],
      council: { consensus: 0.9, verdict: :approved },
      cost: 0.01,
      rounds: 1
    })
    
    mock_chamber.expect(:deliberate, mock_result, [String, Hash])
    
    MASTER::Chamber.stub :new, mock_chamber do
      output = capture_io do
        MASTER::Commands.send(:refactor, "#{@test_file} --raw")
      end.join
      
      # Should show full output in raw mode
      assert_match /class Calculator/, output
      assert_match /plus/, output  # Modified version
      refute_match /---/, output   # No diff markers
    end
    
    mock_chamber.verify
  end

  def test_refactor_apply_mode_accepts_changes
    modified = @original_content.gsub("add", "plus")
    
    mock_chamber = Minitest::Mock.new
    mock_result = MASTER::Result.ok({
      final: modified,
      proposals: [{ model: :test, proposal: modified }],
      council: { consensus: 0.9, verdict: :approved },
      cost: 0.01,
      rounds: 1
    })
    
    mock_chamber.expect(:deliberate, mock_result, [String, Hash])
    
    MASTER::Chamber.stub :new, mock_chamber do
      # Simulate user typing "y" and pressing enter
      simulate_stdin("y\n") do
        output = capture_io do
          MASTER::Commands.send(:refactor, "#{@test_file} --apply")
        end.join
        
        # Should show confirmation prompt and success message
        assert_match /Apply these changes/, output
        assert_match /Changes applied/, output
      end
    end
    
    # Verify file was actually modified
    assert_equal modified, File.read(@test_file)
    
    # Verify undo is available
    assert MASTER::Undo.can_undo?
    
    mock_chamber.verify
  end

  def test_refactor_apply_mode_rejects_changes
    modified = @original_content.gsub("add", "plus")
    
    mock_chamber = Minitest::Mock.new
    mock_result = MASTER::Result.ok({
      final: modified,
      proposals: [{ model: :test, proposal: modified }],
      council: { consensus: 0.9, verdict: :approved },
      cost: 0.01,
      rounds: 1
    })
    
    mock_chamber.expect(:deliberate, mock_result, [String, Hash])
    
    MASTER::Chamber.stub :new, mock_chamber do
      # Simulate user typing "n" and pressing enter
      simulate_stdin("n\n") do
        output = capture_io do
          MASTER::Commands.send(:refactor, "#{@test_file} --apply")
        end.join
        
        # Should show rejection message
        assert_match /Apply these changes/, output
        assert_match /Changes not applied/, output
      end
    end
    
    # Verify file was NOT modified
    assert_equal @original_content, File.read(@test_file)
    
    # Verify undo is NOT available
    refute MASTER::Undo.can_undo?
    
    mock_chamber.verify
  end

  private

  def simulate_stdin(input)
    original_stdin = $stdin
    $stdin = StringIO.new(input)
    yield
  ensure
    $stdin = original_stdin
  end

  def capture_io
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    
    yield
    
    [$stdout.string, $stderr.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end
