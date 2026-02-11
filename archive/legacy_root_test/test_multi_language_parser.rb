# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/parser/multi_language'

class TestMultiLanguageParser < Minitest::Test
  def setup
    @parser = MASTER::Parser::MultiLanguage
  end

  def test_detects_shell_script_by_shebang
    content = "#!/bin/bash\necho 'hello'"
    parser = @parser.new(content)
    assert parser.shell_script?
  end

  def test_detects_shell_script_by_zsh_shebang
    content = "#!/bin/zsh\necho 'hello'"
    parser = @parser.new(content)
    assert parser.shell_script?
  end

  def test_detects_shell_script_by_extension
    content = "echo 'hello'"
    parser = @parser.new(content, file_path: "script.sh")
    assert parser.shell_script?
  end

  def test_does_not_detect_non_shell
    content = "class Foo; end"
    parser = @parser.new(content, file_path: "foo.rb")
    refute parser.shell_script?
  end

  def test_parses_simple_shell_script
    content = <<~SHELL
      #!/bin/bash
      echo "Hello World"
    SHELL

    result = @parser.new(content).parse
    assert_equal :shell, result[:type]
    assert_equal content, result[:shell_code]
    assert_empty result[:language_blocks]
  end

  def test_extracts_ruby_heredoc
    content = <<~SHELL
      #!/bin/bash
      echo "Starting Ruby"
      
      ruby <<-RUBY
        class Foo
          def bar
            puts "hello"
          end
        end
      RUBY
      
      echo "Done"
    SHELL

    result = @parser.new(content).parse
    assert_equal :shell, result[:type]
    refute_empty result[:embedded][:ruby]
    
    ruby_block = result[:embedded][:ruby].first
    assert_equal :ruby, ruby_block[:language]
    assert_includes ruby_block[:code], "class Foo"
    assert_includes ruby_block[:code], "def bar"
    assert ruby_block[:start_line] > 0
  end

  def test_extracts_multiple_heredocs
    content = <<~SHELL
      #!/bin/bash
      
      ruby <<-RUBY
        puts "first"
      RUBY
      
      echo "middle"
      
      ruby <<-RUBY
        puts "second"
      RUBY
    SHELL

    result = @parser.new(content).parse
    assert_equal 2, result[:embedded][:ruby].length
    
    first = result[:embedded][:ruby][0]
    second = result[:embedded][:ruby][1]
    
    assert_includes first[:code], "first"
    assert_includes second[:code], "second"
    assert first[:start_line] < second[:start_line]
  end

  def test_preserves_line_numbers
    content = <<~SHELL
      #!/bin/bash
      # Line 2
      # Line 3
      ruby <<-RUBY
        # Ruby code on line 5
        puts "hello"
      RUBY
    SHELL

    result = @parser.new(content).parse
    ruby_block = result[:embedded][:ruby].first
    
    # The heredoc marker "<<-RUBY" is on line 4
    # The actual Ruby code starts on line 5
    assert_equal 5, ruby_block[:start_line]
  end

  def test_handles_python_heredoc
    content = <<~SHELL
      #!/bin/bash
      
      python <<-PYTHON
        def hello():
            print("world")
      PYTHON
    SHELL

    result = @parser.new(content).parse
    assert_equal :shell, result[:type]
    refute_empty result[:embedded][:python]
    
    python_block = result[:embedded][:python].first
    assert_equal :python, python_block[:language]
    assert_includes python_block[:code], "def hello"
  end

  def test_handles_mixed_languages
    content = <<~SHELL
      #!/bin/bash
      
      ruby <<-RUBY
        puts "Ruby"
      RUBY
      
      python <<-PYTHON
        print("Python")
      PYTHON
    SHELL

    result = @parser.new(content).parse
    assert_equal 1, result[:embedded][:ruby].length
    assert_equal 1, result[:embedded][:python].length
    assert_equal 2, result[:language_blocks].length
  end

  def test_sorts_language_blocks_by_line_number
    content = <<~SHELL
      #!/bin/bash
      
      ruby <<-RUBY
        puts "first"
      RUBY
      
      python <<-PYTHON
        print("second")
      PYTHON
      
      ruby <<-RUBY
        puts "third"
      RUBY
    SHELL

    result = @parser.new(content).parse
    blocks = result[:language_blocks]
    
    # Verify blocks are sorted by start_line
    assert_equal 3, blocks.length
    assert blocks[0][:start_line] < blocks[1][:start_line]
    assert blocks[1][:start_line] < blocks[2][:start_line]
  end

  def test_parse_file_class_method
    require 'tempfile'
    
    Tempfile.create(['test_script', '.sh']) do |file|
      file.write(<<~SHELL)
        #!/bin/bash
        ruby <<-RUBY
          puts "hello"
        RUBY
      SHELL
      file.flush
      
      result = @parser.parse_file(file.path)
      assert_equal :shell, result[:type]
      refute_empty result[:embedded][:ruby]
    end
  end

  def test_handles_no_content
    parser = @parser.new(nil)
    result = parser.parse
    assert result[:error]
  end

  def test_handles_custom_heredoc_markers
    content = <<~SHELL
      #!/bin/bash
      
      ruby <<-RUBY_CODE
        puts "custom marker"
      RUBY_CODE
    SHELL

    result = @parser.new(content).parse
    refute_empty result[:embedded][:ruby]
    
    ruby_block = result[:embedded][:ruby].first
    assert_equal "RUBY_CODE", ruby_block[:marker]
  end
end
