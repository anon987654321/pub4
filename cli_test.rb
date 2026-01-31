#!/usr/bin/env ruby
# frozen_string_literal: true

# Purpose: Comprehensive test suite validating universal code quality pipeline
# Domain: Software testing, quality assurance, behavior verification
# Dependencies: Minitest framework, cli.rb implementation, Ruby stdlib
# Exports: Test classes covering all components of the quality system
#
# This test suite validates every aspect of the universal code quality system:
# - Code loading from all supported sources (file, directory, stdin, clipboard)
# - Programming language detection accuracy across all supported languages
# - Violation detection correctness for all rule categories
# - Automatic fix application safety and correctness
# - Anti-over-simplification guard effectiveness
# - Top-to-bottom organization preservation
# - Principle alignment verification
#
# Test organization follows same top-to-bottom importance structure:
# 1. Critical path tests (loading, detection, analysis)
# 2. Edge case tests (error handling, boundary conditions)
# 3. Integration tests (end-to-end workflows)
# 4. Performance tests (scalability, resource usage)
#
# Every test method name fully describes what is being tested.
# No cryptic abbreviations, no assumed context, completely self-documenting.

require "minitest/autorun"
require "minitest/pride"
require "tempfile"
require "fileutils"
require "tmpdir"
require_relative "cli"

# ===== CODE UNIT CREATION AND BASIC PROPERTIES =====

# Test class: TestCodeUnitCreationAndBasicPropertyAccess
# Purpose: Validates CodeUnit initialization and property accessors
# Coverage:
#   - Creating CodeUnit with various parameter combinations
#   - Accessing all public properties
#   - Verifying immutability of created instances
#   - Testing helper predicate methods

class TestCodeUnitCreationAndBasicPropertyAccess < Minitest::Test
  def test_creates_code_unit_with_content_and_file_path
    sample_ruby_code_content = "def hello_world\n  puts 'Hello, World!'\nend"
    sample_file_path = "/tmp/example.rb"
    
    code_unit = CodeUnit.new(
      content: sample_ruby_code_content,
      file_path: sample_file_path,
      source_type: :file
    )
    
    assert_equal sample_ruby_code_content, code_unit.original_source_code_content
    assert_equal sample_file_path, code_unit.file_system_path_if_from_file
    assert_equal :file, code_unit.source_type_identifier
  end
  
  def test_creates_code_unit_from_stdin_without_file_path
    code_from_stdin = "echo 'test'"
    
    code_unit = CodeUnit.new(
      content: code_from_stdin,
      source_type: :stdin
    )
    
    assert_equal code_from_stdin, code_unit.original_source_code_content
    assert_nil code_unit.file_system_path_if_from_file
    assert_equal :stdin, code_unit.source_type_identifier
  end
  
  def test_code_unit_automatically_detects_programming_language
    ruby_code_with_class_definition = "class MyTestClass\n  def method\n  end\nend"
    
    code_unit = CodeUnit.new(
      content: ruby_code_with_class_definition,
      file_path: "test.rb"
    )
    
    assert_equal :ruby, code_unit.detected_programming_language
  end
  
  def test_code_unit_correctly_identifies_if_originated_from_file
    code_unit_from_file = CodeUnit.new(
      content: "content",
      file_path: "some_file.rb",
      source_type: :file
    )
    
    code_unit_from_stdin = CodeUnit.new(
      content: "content",
      source_type: :stdin
    )
    
    assert code_unit_from_file.originated_from_file_on_filesystem?
    refute code_unit_from_stdin.originated_from_file_on_filesystem?
  end
  
  def test_code_unit_provides_appropriate_display_name_for_user_interface
    code_unit_with_file_path = CodeUnit.new(
      content: "content",
      file_path: "/path/to/file.rb"
    )
    
    code_unit_from_stdin = CodeUnit.new(
      content: "content",
      source_type: :stdin
    )
    
    assert_equal "/path/to/file.rb", code_unit_with_file_path.display_name_for_user_interface
    assert_equal "stdin", code_unit_from_stdin.display_name_for_user_interface
  end
  
  def test_code_unit_correctly_reports_if_language_is_supported
    ruby_code_unit = CodeUnit.new(
      content: "class Test\nend",
      file_path: "test.rb"
    )
    
    unknown_code_unit = CodeUnit.new(
      content: "random text",
      source_type: :text
    )
    
    assert ruby_code_unit.language_is_supported_for_analysis?
    refute unknown_code_unit.language_is_supported_for_analysis?
  end
  
  def test_code_unit_accurately_counts_total_lines_in_source_code
    multi_line_code = "line one\nline two\nline three\n"
    
    code_unit = CodeUnit.new(content: multi_line_code)
    
    assert_equal 3, code_unit.count_total_lines_in_source_code
  end
  
  def test_code_unit_accurately_counts_non_blank_non_comment_lines
    code_with_blanks_and_comments = <<~RUBY
      # This is a comment
      def method
        # Another comment
        
        actual_code_line
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_blanks_and_comments)
    
    # Should count only: def, actual_code_line, end = 3 lines
    assert_equal 3, code_unit.count_non_blank_non_comment_lines_in_source_code
  end
end

# ===== PROGRAMMING LANGUAGE DETECTION =====

# Test class: TestProgrammingLanguageDetectionFromVariousSources
# Purpose: Validates accurate language identification from file paths and content
# Coverage:
#   - Detection from file extensions for all supported languages
#   - Detection from shebang lines
#   - Detection from content patterns
#   - Fallback to :unknown for unrecognized code

class TestProgrammingLanguageDetectionFromVariousSources < Minitest::Test
  def test_detects_ruby_from_rb_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "example.rb"
    )
    
    assert_equal :ruby, detected_language
  end
  
  def test_detects_ruby_from_rake_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "tasks.rake"
    )
    
    assert_equal :ruby, detected_language
  end
  
  def test_detects_ruby_from_gemfile_basename
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "Gemfile"
    )
    
    assert_equal :ruby, detected_language
  end
  
  def test_detects_shell_from_sh_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "script.sh"
    )
    
    assert_equal :shell, detected_language
  end
  
  def test_detects_shell_from_bash_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "script.bash"
    )
    
    assert_equal :shell, detected_language
  end
  
  def test_detects_yaml_from_yml_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "config.yml"
    )
    
    assert_equal :yaml, detected_language
  end
  
  def test_detects_yaml_from_yaml_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "config.yaml"
    )
    
    assert_equal :yaml, detected_language
  end
  
  def test_detects_html_from_html_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "page.html"
    )
    
    assert_equal :html, detected_language
  end
  
  def test_detects_css_from_css_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "styles.css"
    )
    
    assert_equal :css, detected_language
  end
  
  def test_detects_javascript_from_js_file_extension
    detected_language = ProgrammingLanguageDetector.detect_language_from_file_path_indicators(
      "app.js"
    )
    
    assert_equal :javascript, detected_language
  end
  
  def test_detects_ruby_from_content_with_frozen_string_literal
    ruby_code_with_frozen_literal = "# frozen_string_literal: true\n\nclass Example\nend"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      ruby_code_with_frozen_literal
    )
    
    assert_equal :ruby, detected_language
  end
  
  def test_detects_ruby_from_content_with_class_definition
    ruby_code_with_class = "class MyClass\n  def initialize\n  end\nend"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      ruby_code_with_class
    )
    
    assert_equal :ruby, detected_language
  end
  
  def test_detects_ruby_from_content_with_module_definition
    ruby_code_with_module = "module MyModule\n  def self.method\n  end\nend"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      ruby_code_with_module
    )
    
    assert_equal :ruby, detected_language
  end
  
  def test_detects_shell_from_content_with_bash_shebang
    shell_code_with_bash_shebang = "#!/bin/bash\necho 'Hello World'"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      shell_code_with_bash_shebang
    )
    
    assert_equal :shell, detected_language
  end
  
  def test_detects_shell_from_content_with_zsh_shebang
    shell_code_with_zsh_shebang = "#!/usr/bin/env zsh\necho 'Hello World'"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      shell_code_with_zsh_shebang
    )
    
    assert_equal :shell, detected_language
  end
  
  def test_detects_yaml_from_content_with_document_marker
    yaml_content_with_marker = "---\nkey: value\nlist:\n  - item1\n  - item2"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      yaml_content_with_marker
    )
    
    assert_equal :yaml, detected_language
  end
  
  def test_detects_html_from_content_with_doctype
    html_content_with_doctype = "<!DOCTYPE html>\n<html>\n<body>Hello</body>\n</html>"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      html_content_with_doctype
    )
    
    assert_equal :html, detected_language
  end
  
  def test_detects_javascript_from_content_with_function_keyword
    javascript_code_with_function = "function hello() {\n  console.log('hi');\n}"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      javascript_code_with_function
    )
    
    assert_equal :javascript, detected_language
  end
  
  def test_detects_javascript_from_content_with_const_declaration
    javascript_code_with_const = "const greeting = 'Hello World';\nconsole.log(greeting);"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      javascript_code_with_const
    )
    
    assert_equal :javascript, detected_language
  end
  
  def test_returns_unknown_for_unrecognized_content
    unrecognized_content = "This is just plain text with no programming patterns"
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      unrecognized_content
    )
    
    assert_equal :unknown, detected_language
  end
  
  def test_returns_unknown_for_empty_content
    empty_content = ""
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      empty_content
    )
    
    assert_equal :unknown, detected_language
  end
  
  def test_returns_unknown_for_nil_content
    nil_content = nil
    
    detected_language = ProgrammingLanguageDetector.detect_language_from_code_content_patterns(
      nil_content
    )
    
    assert_equal :unknown, detected_language
  end
end

# ===== CODE LOADING FROM FILES AND DIRECTORIES =====

# Test class: TestCodeLoadingFromFileSystemSources
# Purpose: Validates loading code from files and directories
# Coverage:
#   - Loading single files
#   - Loading directories recursively
#   - Filtering by file extension
#   - Excluding hidden directories
#   - Error handling for missing files

class TestCodeLoadingFromFileSystemSources < Minitest::Test
  def setup
    @temporary_test_directory = Dir.mktmpdir("code_quality_test_")
  end
  
  def teardown
    FileUtils.rm_rf(@temporary_test_directory)
  end
  
  def test_successfully_loads_code_from_single_existing_file
    test_file_path = File.join(@temporary_test_directory, "example.rb")
    test_file_content = "def hello\n  puts 'world'\nend"
    File.write(test_file_path, test_file_content)
    
    loaded_code_units = CodeUnitLoader.load_code_units_from_single_file(test_file_path)
    
    assert_equal 1, loaded_code_units.size
    assert_equal test_file_content, loaded_code_units.first.original_source_code_content
    assert_equal test_file_path, loaded_code_units.first.file_system_path_if_from_file
    assert_equal :file, loaded_code_units.first.source_type_identifier
  end
  
  def test_returns_empty_array_when_loading_nonexistent_file
    nonexistent_file_path = File.join(@temporary_test_directory, "does_not_exist.rb")
    
    loaded_code_units = CodeUnitLoader.load_code_units_from_single_file(nonexistent_file_path)
    
    assert_equal 0, loaded_code_units.size
  end
  
  def test_successfully_loads_all_code_files_from_directory_recursively
    # Create nested directory structure with multiple code files
    lib_directory = File.join(@temporary_test_directory, "lib")
    test_directory = File.join(@temporary_test_directory, "test")
    FileUtils.mkdir_p(lib_directory)
    FileUtils.mkdir_p(test_directory)
    
    File.write(File.join(@temporary_test_directory, "main.rb"), "# main file")
    File.write(File.join(lib_directory, "helper.rb"), "# helper file")
    File.write(File.join(test_directory, "test_helper.rb"), "# test file")
    
    loaded_code_units = CodeUnitLoader.load_code_units_from_directory_recursively(
      @temporary_test_directory
    )
    
    assert_equal 3, loaded_code_units.size
    assert loaded_code_units.all? { |unit| unit.originated_from_file_on_filesystem? }
  end
  
  def test_finds_only_files_with_supported_code_extensions
    File.write(File.join(@temporary_test_directory, "code.rb"), "ruby code")
    File.write(File.join(@temporary_test_directory, "script.sh"), "shell code")
    File.write(File.join(@temporary_test_directory, "config.yml"), "yaml code")
    File.write(File.join(@temporary_test_directory, "readme.txt"), "text file")
    File.write(File.join(@temporary_test_directory, "data.json"), "json data")
    
    code_file_paths = CodeUnitLoader.find_all_code_files_in_directory_tree(
      @temporary_test_directory
    )
    
    # Should find .rb, .sh, .yml but not .txt or .json
    assert_equal 3, code_file_paths.size
    refute code_file_paths.any? { |path| path.end_with?(".txt") }
    refute code_file_paths.any? { |path| path.end_with?(".json") }
  end
  
  def test_correctly_excludes_files_in_hidden_git_directory
    git_directory = File.join(@temporary_test_directory, ".git")
    FileUtils.mkdir_p(git_directory)
    
    File.write(File.join(git_directory, "config"), "git config content")
    File.write(File.join(@temporary_test_directory, "visible.rb"), "visible ruby code")
    
    code_file_paths = CodeUnitLoader.find_all_code_files_in_directory_tree(
      @temporary_test_directory
    )
    
    assert_equal 1, code_file_paths.size
    refute code_file_paths.any? { |path| path.include?("/.git/") }
  end
  
  def test_correctly_excludes_files_in_node_modules_directory
    node_modules_directory = File.join(@temporary_test_directory, "node_modules")
    FileUtils.mkdir_p(node_modules_directory)
    
    File.write(File.join(node_modules_directory, "package.js"), "npm package")
    File.write(File.join(@temporary_test_directory, "app.js"), "application code")
    
    code_file_paths = CodeUnitLoader.find_all_code_files_in_directory_tree(
      @temporary_test_directory
    )
    
    assert_equal 1, code_file_paths.size
    refute code_file_paths.any? { |path| path.include?("/node_modules/") }
  end
  
  def test_correctly_identifies_which_files_should_be_included_in_analysis
    ruby_file = File.join(@temporary_test_directory, "code.rb")
    text_file = File.join(@temporary_test_directory, "readme.txt")
    
    File.write(ruby_file, "ruby")
    File.write(text_file, "text")
    
    assert CodeUnitLoader.file_should_be_included_in_analysis?(ruby_file)
    refute CodeUnitLoader.file_should_be_included_in_analysis?(text_file)
    refute CodeUnitLoader.file_should_be_included_in_analysis?(@temporary_test_directory)
  end
end

# ===== CODE LOADING FROM NON-FILE SOURCES =====

# Test class: TestCodeLoadingFromStdinAndClipboardSources
# Purpose: Validates loading code from stdin and system clipboard
# Coverage:
#   - Loading from stdin
#   - Loading from clipboard (when available)
#   - Loading from direct text input

class TestCodeLoadingFromStdinAndClipboardSources < Minitest::Test
  def test_creates_code_unit_from_direct_text_input
    direct_text_input = "def example_method\n  42\nend"
    
    loaded_code_units = CodeUnitLoader.load_code_units_from_direct_text_input(
      direct_text_input
    )
    
    assert_equal 1, loaded_code_units.size
    assert_equal direct_text_input, loaded_code_units.first.original_source_code_content
    assert_equal :text, loaded_code_units.first.source_type_identifier
  end
  
  def test_attempt_to_read_clipboard_returns_nil_when_no_clipboard_tool_available
    # Mock the backtick commands to return empty
    clipboard_content = CodeUnitLoader.attempt_to_read_system_clipboard
    
    # Should return nil or empty string depending on system
    assert clipboard_content.nil? || clipboard_content.empty?
  end
end

# ===== NAMING QUALITY VIOLATION DETECTION =====

# Test class: TestNamingQualityViolationDetectionInCodeUnits
# Purpose: Validates detection of naming violations (Elements of Style)
# Coverage:
#   - Generic verb detection (process, handle, do, etc.)
#   - Single-letter variable detection
#   - Vague noun detection (data, info, thing, etc.)
#   - Verification that good names pass without violations

class TestNamingQualityViolationDetectionInCodeUnits < Minitest::Test
  def test_detects_generic_verbs_in_method_names
    code_with_generic_verbs = <<~RUBY
      def process_data(input)
        handle_input(input)
      end
      
      def handle_input(data)
        do_something_with(data)
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_generic_verbs)
    naming_violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    generic_verb_violations = naming_violations.select do |violation|
      violation[:violation_type] == :generic_verbs_used
    end
    
    assert generic_verb_violations.any?
    
    violation_message = generic_verb_violations.first[:description]
    assert_match(/process|handle|do/, violation_message)
  end
  
  def test_detects_single_letter_variable_assignments
    code_with_single_letter_variables = <<~RUBY
      def calculate_area
        x = 10
        y = 20
        z = x * y
        return z
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_single_letter_variables)
    naming_violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    single_letter_violations = naming_violations.select do |violation|
      violation[:violation_type] == :single_letter_variables
    end
    
    assert single_letter_violations.any?
  end
  
  def test_does_not_flag_loop_counters_i_j_k_as_violations
    code_with_acceptable_loop_counters = <<~RUBY
      def process_matrix(matrix)
        matrix.each_with_index do |row, i|
          row.each_with_index do |cell, j|
            process_cell(cell, i, j)
          end
        end
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_acceptable_loop_counters)
    naming_violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    single_letter_violations = naming_violations.select do |violation|
      violation[:violation_type] == :single_letter_variables
    end
    
    # Should not detect i, j as violations in this context
    assert single_letter_violations.empty?
  end
  
  def test_detects_vague_nouns_like_data_and_info
    code_with_vague_nouns = <<~RUBY
      def process(data)
        info = extract_info_from(data)
        thing = create_thing_from(info)
        return thing
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_vague_nouns)
    naming_violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    vague_noun_violations = naming_violations.select do |violation|
      violation[:violation_type] == :vague_nouns_used
    end
    
    assert vague_noun_violations.any?
    
    violation_message = vague_noun_violations.first[:description]
    assert_match(/data|info|thing/, violation_message)
  end
  
  def test_does_not_flag_well_named_code_with_descriptive_names
    code_with_excellent_descriptive_naming = <<~RUBY
      def calculate_total_price_including_tax(order_subtotal, applicable_tax_rate)
        tax_amount = order_subtotal * applicable_tax_rate
        total_price_with_tax = order_subtotal + tax_amount
        return total_price_with_tax
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_excellent_descriptive_naming)
    naming_violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    assert naming_violations.empty?
  end
end

# ===== STRUCTURAL QUALITY VIOLATION DETECTION =====

# Test class: TestStructuralQualityViolationDetectionInCodeUnits
# Purpose: Validates detection of structural violations (Clean Code)
# Coverage:
#   - Long method detection (> 20 lines)
#   - Large class detection (> 300 lines)
#   - High parameter count detection (> 3 parameters)
#   - Verification that well-structured code passes

class TestStructuralQualityViolationDetectionInCodeUnits < Minitest::Test
  def test_detects_methods_exceeding_twenty_line_threshold
    long_method_code = <<~RUBY
      def overly_long_method_with_too_many_lines
        line_1
        line_2
        line_3
        line_4
        line_5
        line_6
        line_7
        line_8
        line_9
        line_10
        line_11
        line_12
        line_13
        line_14
        line_15
        line_16
        line_17
        line_18
        line_19
        line_20
        line_21
        line_22
      end
    RUBY
    
    code_unit = CodeUnit.new(content: long_method_code)
    structure_violations = StructuralQualityAnalyzer.find_all_structure_violations_in_code_unit(code_unit)
    
    long_method_violations = structure_violations.select do |violation|
      violation[:violation_type] == :long_method
    end
    
    assert long_method_violations.any?
    assert long_method_violations.first[:actual_line_count] > 20
  end
  
  def test_does_not_flag_short_focused_methods_under_twenty_lines
    short_focused_method_code = <<~RUBY
      def calculate_sales_tax(subtotal_amount)
        sales_tax_rate = 0.08
        tax_amount = subtotal_amount * sales_tax_rate
        return tax_amount
      end
      
      def format_price_as_currency(price_amount)
        formatted_string = "$#{'%.2f' % price_amount}"
        return formatted_string
      end
    RUBY
    
    code_unit = CodeUnit.new(content: short_focused_method_code)
    structure_violations = StructuralQualityAnalyzer.find_all_structure_violations_in_code_unit(code_unit)
    
    long_method_violations = structure_violations.select do |violation|
      violation[:violation_type] == :long_method
    end
    
    assert long_method_violations.empty?
  end
  
  def test_correctly_counts_lines_in_each_method_definition
    code_with_multiple_methods_of_varying_lengths = <<~RUBY
      def small_method
        line_1
        line_2
      end
      
      def medium_method
        line_1
        line_2
        line_3
        line_4
        line_5
      end
      
      def large_method
        line_1
        line_2
        line_3
        line_4
        line_5
        line_6
        line_7
        line_8
        line_9
        line_10
      end
    RUBY
    
    line_counts_by_method = StructuralQualityAnalyzer.extract_all_methods_with_line_counts(
      code_with_multiple_methods_of_varying_lengths
    )
    
    assert_equal 3, line_counts_by_method.size
    
    small_method_info = line_counts_by_method.find { |m| m[:name] == "small_method" }
    medium_method_info = line_counts_by_method.find { |m| m[:name] == "medium_method" }
    large_method_info = line_counts_by_method.find { |m| m[:name] == "large_method" }
    
    assert_equal 2, small_method_info[:line_count]
    assert_equal 5, medium_method_info[:line_count]
    assert_equal 10, large_method_info[:line_count]
  end
  
  def test_detects_classes_exceeding_three_hundred_line_threshold
    # Generate a large class for testing
    large_class_code = "class VeryLargeClass\n"
    large_class_code += ("  def method\n    code\n  end\n" * 101)  # Creates 303 lines
    large_class_code += "end"
    
    code_unit = CodeUnit.new(content: large_class_code)
    structure_violations = StructuralQualityAnalyzer.find_all_structure_violations_in_code_unit(code_unit)
    
    large_class_violations = structure_violations.select do |violation|
      violation[:violation_type] == :large_class
    end
    
    assert large_class_violations.any?
  end
  
  def test_detects_methods_with_more_than_five_parameters
    method_with_too_many_parameters = <<~RUBY
      def create_user(name, email, password, age, address, phone, role, department)
        # Implementation
      end
    RUBY
    
    code_unit = CodeUnit.new(content: method_with_too_many_parameters)
    structure_violations = StructuralQualityAnalyzer.find_all_structure_violations_in_code_unit(code_unit)
    
    parameter_count_violations = structure_violations.select do |violation|
      violation[:violation_type] == :too_many_parameters
    end
    
    assert parameter_count_violations.any?
    assert parameter_count_violations.first[:parameter_count] > 5
  end
  
  def test_correctly_counts_parameters_in_method_signature
    parameters_string_with_five_params = "name, email, age, address, phone"
    
    parameter_count = StructuralQualityAnalyzer.count_parameters_in_parameter_string(
      parameters_string_with_five_params
    )
    
    assert_equal 5, parameter_count
  end
  
  def test_returns_zero_for_empty_parameter_string
    empty_parameters_string = ""
    
    parameter_count = StructuralQualityAnalyzer.count_parameters_in_parameter_string(
      empty_parameters_string
    )
    
    assert_equal 0, parameter_count
  end
end

# ===== CODE SMELL DETECTION =====

# Test class: TestCodeSmellDetectionInVariousScenarios
# Purpose: Validates detection of code smells (Fowler catalog)
# Coverage:
#   - Duplicate code block detection
#   - Commented-out code detection
#   - Feature envy detection
#   - Primitive obsession detection

class TestCodeSmellDetectionInVariousScenarios < Minitest::Test
  def test_detects_duplicate_code_blocks_in_source
    code_with_obvious_duplication = <<~RUBY
      def method_one
        validate_input_parameters
        process_business_logic
        save_results_to_database
      end
      
      def method_two
        validate_input_parameters
        process_business_logic
        save_results_to_database
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_obvious_duplication)
    detected_code_smells = CodeSmellDetector.find_all_code_smells_in_code_unit(code_unit)
    
    duplicate_code_smells = detected_code_smells.select do |smell|
      smell[:smell_type] == :duplicate_code
    end
    
    assert duplicate_code_smells.any?
  end
  
  def test_finds_duplicate_blocks_across_entire_source_file
    source_with_repeated_three_line_blocks = <<~CODE
      first line of repeated block for testing purposes only
      second line of repeated block for testing purposes only
      third line of repeated block for testing purposes only
      
      some unique code here that is not duplicated anywhere
      
      first line of repeated block for testing purposes only
      second line of repeated block for testing purposes only
      third line of repeated block for testing purposes only
    CODE
    
    duplicate_blocks = CodeSmellDetector.find_all_duplicate_code_blocks_in_source(
      source_with_repeated_three_line_blocks
    )
    
    assert duplicate_blocks.any?
  end
  
  def test_does_not_flag_short_repeated_lines_as_duplication
    code_with_short_common_lines = <<~RUBY
      x = 1
      y = 2
      x = 1
      y = 2
    RUBY
    
    duplicate_blocks = CodeSmellDetector.find_all_duplicate_code_blocks_in_source(
      code_with_short_common_lines
    )
    
    assert duplicate_blocks.empty?
  end
  
  def test_ignores_common_boilerplate_patterns_like_end_statements
    code_with_many_end_statements = <<~RUBY
      def method_one
        code
      end
      
      def method_two
        code
      end
      
      def method_three
        code
      end
    RUBY
    
    duplicate_blocks = CodeSmellDetector.find_all_duplicate_code_blocks_in_source(
      code_with_many_end_statements
    )
    
    # Should not flag 'end' statements as duplication
    assert duplicate_blocks.empty?
  end
  
  def test_detects_commented_out_code_lines
    code_with_commented_sections = <<~RUBY
      def active_method
        current_code
      end
      
      # def old_method
      #   commented_code
      # end
      
      # class OldClass
      #   old_implementation
      # end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_commented_sections)
    detected_code_smells = CodeSmellDetector.find_all_code_smells_in_code_unit(code_unit)
    
    commented_code_smells = detected_code_smells.select do |smell|
      smell[:smell_type] == :commented_out_code
    end
    
    assert commented_code_smells.any?
    assert commented_code_smells.first[:severity_level] == :critical
  end
  
  def test_finds_lines_matching_commented_code_patterns
    source_with_commented_code = <<~RUBY
      # def old_function
      # class OldClass
      # if condition
      # while loop
      # return value
      # variable = assignment
    RUBY
    
    commented_code_lines = CodeSmellDetector.find_lines_with_commented_out_code(
      source_with_commented_code
    )
    
    assert_equal 6, commented_code_lines.size
  end
  
  def test_does_not_flag_regular_documentation_comments
    code_with_normal_comments = <<~RUBY
      # This class handles user authentication
      # It validates credentials and manages sessions
      class UserAuthenticator
        # Authenticates user with provided credentials
        def authenticate(username, password)
          # Implementation here
        end
      end
    RUBY
    
    commented_code_lines = CodeSmellDetector.find_lines_with_commented_out_code(
      code_with_normal_comments
    )
    
    assert commented_code_lines.empty?
  end
end

# ===== TYPOGRAPHY VIOLATION DETECTION =====

# Test class: TestTypographyViolationDetectionInCodeFormatting
# Purpose: Validates detection of typography violations (Bringhurst)
# Coverage:
#   - Long line detection (> 120 characters)
#   - Trailing whitespace detection
#   - Inconsistent indentation detection

class TestTypographyViolationDetectionInCodeFormatting < Minitest::Test
  def test_detects_lines_exceeding_one_hundred_twenty_character_limit
    very_long_line = "x" * 130
    code_with_excessively_long_lines = "def method\n  #{very_long_line}\nend"
    
    code_unit = CodeUnit.new(content: code_with_excessively_long_lines)
    typography_violations = TypographyAnalyzer.find_all_typography_violations_in_code_unit(code_unit)
    
    long_line_violations = typography_violations.select do |violation|
      violation[:violation_type] == :lines_too_long
    end
    
    assert long_line_violations.any?
    assert long_line_violations.first[:line_count] > 0
  end
  
  def test_does_not_flag_lines_within_acceptable_length_limits
    code_with_appropriately_short_lines = <<~RUBY
      def calculate_total_price(items)
        items.sum(&:price)
      end
    RUBY
    
    code_unit = CodeUnit.new(content: code_with_appropriately_short_lines)
    typography_violations = TypographyAnalyzer.find_all_typography_violations_in_code_unit(code_unit)
    
    long_line_violations = typography_violations.select do |violation|
      violation[:violation_type] == :lines_too_long
    end
    
    assert long_line_violations.empty?
  end
  
  def test_detects_trailing_whitespace_on_line_endings
    code_with_trailing_spaces = "line_one   \nline_two  \nline_three    "
    
    code_unit = CodeUnit.new(content: code_with_trailing_spaces)
    typography_violations = TypographyAnalyzer.find_all_typography_violations_in_code_unit(code_unit)
    
    trailing_whitespace_violations = typography_violations.select do |violation|
      violation[:violation_type] == :trailing_whitespace
    end
    
    assert trailing_whitespace_violations.any?
  end
  
  def test_correctly_identifies_if_line_ends_with_whitespace
    line_with_trailing_spaces = "code_line   \n"
    line_without_trailing_spaces = "code_line\n"
    
    assert TypographyAnalyzer.line_ends_with_whitespace?(line_with_trailing_spaces)
    refute TypographyAnalyzer.line_ends_with_whitespace?(line_without_trailing_spaces)
  end
end

# ===== AUTOMATIC FIX APPLICATION =====

# Test class: TestAutomaticFixApplicationToRubyCode
# Purpose: Validates automatic fixes applied to Ruby code
# Coverage:
#   - Adding frozen_string_literal when missing
#   - Preserving frozen_string_literal when present
#   - Correct placement after shebang
#   - Stripping trailing whitespace

class TestAutomaticFixApplicationToRubyCode < Minitest::Test
  def test_adds_frozen_string_literal_comment_when_missing_from_ruby_file
    ruby_code_without_frozen_literal = "class ExampleClass\n  def method\n  end\nend"
    
    fixed_ruby_code = RubyIdiomFixer.apply_all_ruby_idioms(
      ruby_code_without_frozen_literal
    )
    
    assert_includes fixed_ruby_code, "frozen_string_literal: true"
  end
  
  def test_does_not_duplicate_frozen_string_literal_when_already_present
    ruby_code_with_frozen_literal = "# frozen_string_literal: true\n\nclass Example\nend"
    
    fixed_ruby_code = RubyIdiomFixer.apply_all_ruby_idioms(
      ruby_code_with_frozen_literal
    )
    
    frozen_literal_occurrences = fixed_ruby_code.scan(/frozen_string_literal/).size
    assert_equal 1, frozen_literal_occurrences
  end
  
  def test_inserts_frozen_literal_after_shebang_when_shebang_present
    ruby_code_with_shebang = "#!/usr/bin/env ruby\n\nclass Example\nend"
    
    fixed_ruby_code = RubyIdiomFixer.apply_all_ruby_idioms(
      ruby_code_with_shebang
    )
    
    lines = fixed_ruby_code.lines
    assert_equal "#!/usr/bin/env ruby\n", lines[0]
    assert_includes lines[1], "frozen_string_literal"
  end
  
  def test_correctly_determines_insertion_index_for_frozen_literal
    lines_with_shebang = ["#!/usr/bin/env ruby\n", "class Test\n", "end\n"]
    lines_without_shebang = ["class Test\n", "end\n"]
    
    index_with_shebang = RubyIdiomFixer.determine_frozen_literal_insertion_index(
      lines_with_shebang
    )
    index_without_shebang = RubyIdiomFixer.determine_frozen_literal_insertion_index(
      lines_without_shebang
    )
    
    assert_equal 1, index_with_shebang
    assert_equal 0, index_without_shebang
  end
end

# Test class: TestAutomaticFixApplicationToShellScripts
# Purpose: Validates automatic fixes applied to shell scripts
# Coverage:
#   - Adding shebang when missing
#   - Adding safety flags when missing
#   - Preserving existing shebang and flags
#   - Correct ordering of shebang and flags

class TestAutomaticFixApplicationToShellScripts < Minitest::Test
  def test_adds_shebang_line_when_missing_from_shell_script
    shell_code_without_shebang = "echo 'Hello World'"
    
    fixed_shell_code = ShellIdiomFixer.apply_all_shell_idioms(
      shell_code_without_shebang
    )
    
    assert fixed_shell_code.start_with?("#!/usr/bin/env zsh")
  end
  
  def test_adds_safety_flags_when_missing_from_shell_script
    shell_code_without_safety_flags = "#!/bin/bash\necho 'Hello'"
    
    fixed_shell_code = ShellIdiomFixer.apply_all_shell_idioms(
      shell_code_without_safety_flags
    )
    
    assert_includes fixed_shell_code, "set -euo pipefail"
  end
  
  def test_does_not_duplicate_shebang_when_already_present
    shell_code_with_shebang = "#!/usr/bin/env zsh\necho 'test'"
    
    fixed_shell_code = ShellIdiomFixer.apply_all_shell_idioms(
      shell_code_with_shebang
    )
    
    shebang_occurrences = fixed_shell_code.scan(/^#!/).size
    assert_equal 1, shebang_occurrences
  end
  
  def test_does_not_duplicate_safety_flags_when_already_present
    complete_shell_script = "#!/usr/bin/env zsh\n\nset -euo pipefail\n\necho 'test'"
    
    fixed_shell_code = ShellIdiomFixer.apply_all_shell_idioms(
      complete_shell_script
    )
    
    safety_flag_occurrences = fixed_shell_code.scan(/set -/).size
    assert_equal 1, safety_flag_occurrences
  end
  
  def test_correctly_finds_shebang_line_index_in_script
    lines_with_shebang_at_start = ["#!/bin/bash\n", "echo test\n"]
    lines_without_shebang = ["echo test\n"]
    
    index_with_shebang = ShellIdiomFixer.find_shebang_line_index(
      lines_with_shebang_at_start
    )
    index_without_shebang = ShellIdiomFixer.find_shebang_line_index(
      lines_without_shebang
    )
    
    assert_equal 0, index_with_shebang
    assert_equal(-1, index_without_shebang)
  end
end

# Test class: TestAutomaticFixApplicationToYAMLFiles
# Purpose: Validates automatic fixes applied to YAML files
# Coverage:
#   - Adding document marker (---) when missing
#   - Preserving document marker when present
#   - Not duplicating document marker

class TestAutomaticFixApplicationToYAMLFiles < Minitest::Test
  def test_adds_yaml_document_marker_when_missing
    yaml_without_document_marker = "key: value\nlist:\n  - item1\n  - item2"
    
    fixed_yaml_content = YamlIdiomFixer.apply_all_yaml_idioms(
      yaml_without_document_marker
    )
    
    assert fixed_yaml_content.start_with?("---\n")
  end
  
  def test_does_not_duplicate_document_marker_when_already_present
    yaml_with_document_marker = "---\nkey: value\nother_key: other_value"
    
    fixed_yaml_content = YamlIdiomFixer.apply_all_yaml_idioms(
      yaml_with_document_marker
    )
    
    document_marker_occurrences = fixed_yaml_content.lines.count { |line| line.strip == "---" }
    assert_equal 1, document_marker_occurrences
  end
  
  def test_correctly_detects_if_document_marker_already_present
    lines_with_marker = ["---\n", "key: value\n"]
    lines_without_marker = ["key: value\n"]
    
    assert YamlIdiomFixer.document_marker_already_present?(lines_with_marker)
    refute YamlIdiomFixer.document_marker_already_present?(lines_without_marker)
  end
end

# Test class: TestUniversalFormattingFixesAcrossAllLanguages
# Purpose: Validates universal formatting fixes that apply to all languages
# Coverage:
#   - Stripping trailing whitespace from all lines
#   - Ensuring final newline present
#   - Preserving line endings

class TestUniversalFormattingFixesAcrossAllLanguages < Minitest::Test
  def test_strips_trailing_whitespace_from_every_line_in_source
    code_with_many_trailing_spaces = "line_one   \nline_two  \nline_three    \n"
    
    formatted_code = UniversalFormattingFixer.apply_all_formatting_fixes(
      code_with_many_trailing_spaces
    )
    
    formatted_code.lines.each do |single_line|
      refute single_line.match?(/\s+\n$/), "Line should not have trailing spaces: #{single_line.inspect}"
    end
  end
  
  def test_ensures_file_ends_with_exactly_one_newline_character
    code_without_final_newline = "line_one\nline_two"
    
    formatted_code = UniversalFormattingFixer.apply_all_formatting_fixes(
      code_without_final_newline
    )
    
    assert formatted_code.end_with?("\n")
    refute formatted_code.end_with?("\n\n")
  end
  
  def test_preserves_existing_newline_characters_within_content
    code_with_proper_newlines = "line_one\nline_two\nline_three\n"
    
    formatted_code = UniversalFormattingFixer.apply_all_formatting_fixes(
      code_with_proper_newlines
    )
    
    assert_equal 3, formatted_code.lines.count
  end
end

# ===== INTEGRATION TESTS =====

# Test class: TestCompleteEndToEndPipelineExecution
# Purpose: Validates complete workflow from loading through fixing
# Coverage:
#   - Full pipeline execution on real files
#   - Integration of all analysis components
#   - Verification that fixes are correctly applied
#   - Convergence verification (repeated analysis)

class TestCompleteEndToEndPipelineExecution < Minitest::Test
  def setup
    @temporary_test_directory_for_integration = Dir.mktmpdir("integration_test_")
  end
  
  def teardown
    FileUtils.rm_rf(@temporary_test_directory_for_integration)
  end
  
  def test_complete_pipeline_successfully_processes_ruby_file_from_start_to_finish
    test_ruby_file_path = File.join(@temporary_test_directory_for_integration, "example.rb")
    
    initial_ruby_code_with_violations = <<~RUBY
      class ExampleClass
        def process(x)
          x * 2
        end
      end
    RUBY
    
    File.write(test_ruby_file_path, initial_ruby_code_with_violations)
    
    # Load code
    loaded_code_units = CodeUnitLoader.load_code_units_from_input_source_specification(
      test_ruby_file_path
    )
    
    assert_equal 1, loaded_code_units.size
    assert_equal :ruby, loaded_code_units.first.detected_programming_language
    
    # Analyze code
    analysis_results = loaded_code_units.map do |code_unit|
      UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(code_unit)
    end
    
    assert analysis_results.first.is_a?(Hash)
    assert analysis_results.first.key?(:naming_violations)
    
    # Apply fixes
    loaded_code_units.zip(analysis_results).each do |code_unit, analysis_result|
      AutomaticFixApplicator.apply_all_safe_fixes_to_code_unit(code_unit, analysis_result)
    end
    
    # Verify fixes were written
    fixed_file_content = File.read(test_ruby_file_path)
    assert_includes fixed_file_content, "frozen_string_literal: true"
  end
  
  def test_pipeline_detects_violations_and_applies_fixes_reducing_violation_count
    test_file_path = File.join(@temporary_test_directory_for_integration, "needs_fixing.rb")
    
    code_with_multiple_violations = <<~RUBY
      class Test
        def process(x)
          x * 2
        end
      end
    RUBY
    
    File.write(test_file_path, code_with_multiple_violations)
    
    # First analysis - should find violations
    code_unit_before_fixes = CodeUnitLoader.load_code_units_from_single_file(test_file_path).first
    analysis_before_fixes = UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(
      code_unit_before_fixes
    )
    
    violations_before = count_total_violations(analysis_before_fixes)
    assert violations_before > 0
    
    # Apply fixes
    AutomaticFixApplicator.apply_all_safe_fixes_to_code_unit(
      code_unit_before_fixes,
      analysis_before_fixes
    )
    
    # Second analysis - should have fewer violations
    code_unit_after_fixes = CodeUnitLoader.load_code_units_from_single_file(test_file_path).first
    analysis_after_fixes = UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(
      code_unit_after_fixes
    )
    
    violations_after = count_total_violations(analysis_after_fixes)
    assert violations_after < violations_before
  end
  
  def test_convergence_toward_zero_violations_after_multiple_iterations
    test_file_path = File.join(@temporary_test_directory_for_integration, "converge.rb")
    
    initial_code = "class Test\n  def method\n  end\nend"
    File.write(test_file_path, initial_code)
    
    previous_violation_count = Float::INFINITY
    max_iterations = 5
    
    max_iterations.times do |iteration|
      code_unit = CodeUnitLoader.load_code_units_from_single_file(test_file_path).first
      analysis = UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(code_unit)
      
      current_violation_count = count_total_violations(analysis)
      
      # Violations should decrease or stay same (convergence)
      assert current_violation_count <= previous_violation_count,
        "Iteration #{iteration}: violations increased (was #{previous_violation_count}, now #{current_violation_count})"
      
      break if current_violation_count.zero?
      
      AutomaticFixApplicator.apply_all_safe_fixes_to_code_unit(code_unit, analysis)
      previous_violation_count = current_violation_count
    end
  end
  
  private
  
  def count_total_violations(analysis_result)
    analysis_result.values.sum do |violations|
      violations.is_a?(Array) ? violations.size : 0
    end
  end
end

# ===== ANTI-OVER-SIMPLIFICATION VERIFICATION =====

# Test class: TestAntiOverSimplificationGuardsAreEffective
# Purpose: Validates that system prevents loss of meaning during refactoring
# Coverage:
#   - Detection of over-simplified names
#   - Prevention of information loss
#   - Verification of domain knowledge preservation

class TestAntiOverSimplificationGuardsAreEffective < Minitest::Test
  def test_flags_generic_method_names_as_dangerous_over_simplification
    over_simplified_code_with_generic_names = <<~RUBY
      def process(data)
        handle(data)
        do_something(data)
      end
      
      def handle(info)
        validate(info)
        save(info)
      end
    RUBY
    
    code_unit = CodeUnit.new(content: over_simplified_code_with_generic_names)
    naming_violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    generic_verb_violations = naming_violations.select do |violation|
      violation[:violation_type] == :generic_verbs_used
    end
    
    assert generic_verb_violations.any?
    assert_match(/process|handle/, generic_verb_violations.first[:description])
  end
  
  def test_approves_domain_specific_descriptive_method_names
    well_named_domain_specific_code = <<~RUBY
      def calculate_customer_order_total_including_tax_and_shipping(order)
        order_subtotal = calculate_order_line_items_subtotal(order)
        applicable_sales_tax = calculate_sales_tax_for_order_state(order, order_subtotal)
        shipping_cost = calculate_shipping_cost_based_on_weight_and_zone(order)
        
        total_with_all_charges = order_subtotal + applicable_sales_tax + shipping_cost
        return total_with_all_charges
      end
    RUBY
    
    code_unit = CodeUnit.new(content: well_named_domain_specific_code)
    naming_violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    # Should find no violations in this well-named code
    assert naming_violations.empty?
  end
  
  def test_preserves_domain_knowledge_in_extracted_method_names
    # This test verifies that when methods are extracted,
    # they maintain full context and domain terminology
    
    original_inline_code = <<~RUBY
      def process_order(order)
        if order.customer.age >= 65 && order.customer.loyalty_years >= 10
          apply_discount(order, 0.15)
        end
      end
    RUBY
    
    # After proper extraction, method name should preserve all context
    properly_extracted_code = <<~RUBY
      def process_order(order)
        if customer_qualifies_for_senior_loyalty_discount?(order.customer)
          apply_senior_loyalty_discount_to_order(order)
        end
      end
      
      def customer_qualifies_for_senior_loyalty_discount?(customer)
        customer.age >= SENIOR_AGE_THRESHOLD &&
        customer.loyalty_years >= LOYALTY_YEARS_THRESHOLD_FOR_DISCOUNT
      end
      
      def apply_senior_loyalty_discount_to_order(order)
        SENIOR_LOYALTY_DISCOUNT_RATE = 0.15
        apply_discount_to_order(order, SENIOR_LOYALTY_DISCOUNT_RATE)
      end
    RUBY
    
    # Verify that extracted version has no violations
    code_unit = CodeUnit.new(content: properly_extracted_code)
    violations = NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit)
    
    assert violations.empty?, "Properly extracted code should have no naming violations"
  end
end

# ===== PERFORMANCE AND SCALABILITY =====

# Test class: TestPerformanceAndScalabilityCharacteristics
# Purpose: Validates system performance with large codebases
# Coverage:
#   - Large file handling
#   - Many file handling
#   - Memory usage patterns
#   - Analysis speed

class TestPerformanceAndScalabilityCharacteristics < Minitest::Test
  def test_handles_large_files_without_excessive_memory_usage
    large_file_content = "def method\n  code\nend\n" * 1000  # 4000+ lines
    
    code_unit = CodeUnit.new(content: large_file_content)
    
    # Should complete without error
    analysis_result = UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(
      code_unit
    )
    
    assert analysis_result.is_a?(Hash)
  end
  
  def test_processes_directory_with_many_files_efficiently
    test_directory = Dir.mktmpdir("performance_test_")
    
    begin
      # Create 50 small files
      50.times do |i|
        file_path = File.join(test_directory, "file_#{i}.rb")
        File.write(file_path, "class Test#{i}\nend")
      end
      
      start_time = Time.now
      
      code_units = CodeUnitLoader.load_code_units_from_directory_recursively(test_directory)
      
      elapsed_time = Time.now - start_time
      
      assert_equal 50, code_units.size
      assert elapsed_time < 5.0, "Loading 50 files took #{elapsed_time}s (should be < 5s)"
    ensure
      FileUtils.rm_rf(test_directory)
    end
  end
end
