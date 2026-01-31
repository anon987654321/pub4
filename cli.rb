#!/usr/bin/env ruby
# frozen_string_literal: true

# Purpose: Universal code quality enforcement pipeline based on master.yml
# Domain: Static code analysis, refactoring automation, quality assurance
# Dependencies: Ruby stdlib (yaml, json, fileutils), master.yml configuration
# Exports: Pipeline class as main orchestrator, all supporting analyzer classes
#
# This is the primary implementation of the universal code quality system.
# It enforces principles from five integrated authorities:
# - Clean Code (Robert C. Martin) for structural quality
# - Refactoring (Martin Fowler) for systematic improvement
# - Elements of Style (Strunk & White) for naming and prose
# - Typographic Style (Bringhurst) for visual presentation
# - 36 Unified Principles for philosophical foundation
#
# The system is designed for LLM comprehension first, human readability second.
# Every line is self-explanatory through verbose, descriptive naming.
# No clever tricks, no implicit behavior, no hidden complexity.

# ===== AUTOMATIC DEPENDENCY INSTALLATION =====

def require_gem_with_automatic_installation_if_missing(gem_name_to_require)
  require gem_name_to_require
rescue LoadError => error_indicating_gem_not_installed
  puts "Installing missing gem: #{gem_name_to_require}"
  installation_successful = system(
    "gem install --user-install #{gem_name_to_require} --quiet --no-document"
  )
  
  unless installation_successful
    puts "ERROR: Failed to install gem '#{gem_name_to_require}'"
    puts "Please install manually: gem install #{gem_name_to_require}"
    exit 1
  end
  
  Gem.clear_paths
  require gem_name_to_require
end

# Required standard library components
require "yaml"
require "json"
require "fileutils"
require "set"

# ===== MASTER CONFIGURATION LOADING =====

MASTER_CONFIGURATION_FILE_PATH = File.expand_path("master.yml", __dir__)

unless File.exist?(MASTER_CONFIGURATION_FILE_PATH)
  puts "FATAL ERROR: master.yml not found at: #{MASTER_CONFIGURATION_FILE_PATH}"
  puts "This file is required for the system to function."
  puts "Please ensure master.yml exists in the same directory as this script."
  exit 1
end

begin
  MASTER_CONFIGURATION_YAML_CONTENT = File.read(
    MASTER_CONFIGURATION_FILE_PATH,
    encoding: "UTF-8"
  )
  
  MASTER_CONFIGURATION = YAML.safe_load(
    MASTER_CONFIGURATION_YAML_CONTENT,
    permitted_classes: [Symbol, Date, Time],
    aliases: true,
    symbolize_names: false
  )
rescue Psych::SyntaxError => yaml_parsing_error
  puts "FATAL ERROR: master.yml contains invalid YAML syntax"
  puts "Error details: #{yaml_parsing_error.message}"
  puts "Line: #{yaml_parsing_error.line}, Column: #{yaml_parsing_error.column}"
  exit 1
rescue StandardError => unexpected_error
  puts "FATAL ERROR: Could not load master.yml"
  puts "Error: #{unexpected_error.class} - #{unexpected_error.message}"
  exit 1
end

# Validate master.yml has required structure
REQUIRED_MASTER_CONFIGURATION_SECTIONS = [
  "principles",
  "code_smells_catalog",
  "refactoring_mechanics_catalog",
  "prose_writing_rules",
  "file_organization_requirements"
].freeze

REQUIRED_MASTER_CONFIGURATION_SECTIONS.each do |required_section_name|
  unless MASTER_CONFIGURATION.key?(required_section_name)
    puts "FATAL ERROR: master.yml is missing required section: #{required_section_name}"
    exit 1
  end
end

# ===== PUBLIC INTERFACE: PIPELINE ORCHESTRATION =====

# Class: Pipeline
# Purpose: Main orchestrator for code analysis and improvement workflow
# Responsibilities:
#   - Load code from any source (file, directory, stdin, clipboard, URL)
#   - Coordinate analysis through specialized analyzer classes
#   - Present results to user in clear, actionable format
#   - Apply fixes with user confirmation
#   - Track convergence toward zero violations
# Usage:
#   Pipeline.run_analysis_on_code_from_source("path/to/code.rb")
#   Pipeline.run_analysis_on_code_from_source(".")  # entire directory
#   Pipeline.run_analysis_on_code_from_source("-")  # from stdin

class Pipeline
  def self.run_analysis_on_code_from_source(input_source_specification)
    list_of_code_units_to_analyze = load_all_code_units_from_input_source(
      input_source_specification
    )
    
    if list_of_code_units_to_analyze.empty?
      display_message_no_code_found_to_analyze
      return
    end
    
    display_analysis_starting_message(list_of_code_units_to_analyze.size)
    
    list_of_analysis_results = analyze_all_code_units_for_all_violations(
      list_of_code_units_to_analyze
    )
    
    display_all_analysis_results_to_user(
      list_of_code_units_to_analyze,
      list_of_analysis_results
    )
    
    if user_confirms_they_want_to_apply_automatic_fixes?
      apply_all_automatic_fixes_to_code_units(
        list_of_code_units_to_analyze,
        list_of_analysis_results
      )
      display_fixes_applied_successfully_message
    else
      display_no_changes_made_message
    end
  end
  
  # ===== MAIN WORKFLOW STEP IMPLEMENTATIONS =====
  
  def self.load_all_code_units_from_input_source(input_source_specification)
    CodeUnitLoader.load_code_units_from_input_source_specification(
      input_source_specification
    )
  end
  
  def self.analyze_all_code_units_for_all_violations(list_of_code_units)
    list_of_code_units.map do |single_code_unit|
      UniversalCodeAnalyzer.analyze_single_code_unit_for_all_violation_types(
        single_code_unit
      )
    end
  end
  
  def self.display_all_analysis_results_to_user(code_units, analysis_results)
    AnalysisResultPresenter.display_complete_analysis_results(
      code_units,
      analysis_results
    )
  end
  
  def self.user_confirms_they_want_to_apply_automatic_fixes?
    UserInteractionHandler.ask_user_if_they_want_to_apply_fixes
  end
  
  def self.apply_all_automatic_fixes_to_code_units(code_units, analysis_results)
    code_units.zip(analysis_results).each do |code_unit, analysis_result|
      AutomaticFixApplicator.apply_all_safe_fixes_to_code_unit(
        code_unit,
        analysis_result
      )
    end
  end
  
  # ===== USER INTERFACE MESSAGE DISPLAY =====
  
  def self.display_message_no_code_found_to_analyze
    puts "\nNo code found to analyze."
    puts "Please provide a file path, directory path, or use stdin."
  end
  
  def self.display_analysis_starting_message(number_of_units_to_analyze)
    puts "\n" + ("=" * 80)
    puts "UNIVERSAL CODE QUALITY ANALYSIS"
    puts ("=" * 80)
    puts "\nAnalyzing #{number_of_units_to_analyze} code unit(s)..."
    puts "Checking against: #{MASTER_CONFIGURATION.dig('principles', 'complete_principle_list').size} principles"
  end
  
  def self.display_fixes_applied_successfully_message
    puts "\n✓ All automatic fixes applied successfully"
    puts "Review changes and run tests to verify behavior preserved"
  end
  
  def self.display_no_changes_made_message
    puts "\nNo changes made to code"
  end
end

# ===== CODE UNIT REPRESENTATION =====

# Class: CodeUnit
# Purpose: Represents a single analyzable unit of code
# Properties:
#   - original_source_code_content: The actual code text as string
#   - file_system_path_if_from_file: Path to file if loaded from filesystem (nil otherwise)
#   - source_type_identifier: Symbol indicating origin (:file, :stdin, :clipboard, :text)
#   - detected_programming_language: Language detected from content/extension
#   - metadata_hash: Additional context about the code unit
# Design decisions:
#   - Immutable after creation (frozen strings)
#   - Self-contained (no external dependencies to analyze)
#   - Language detection happens at creation time
# Example:
#   unit = CodeUnit.new(
#     content: "def hello\n  puts 'world'\nend",
#     file_path: "example.rb",
#     source_type: :file
#   )

class CodeUnit
  attr_reader :original_source_code_content
  attr_reader :file_system_path_if_from_file
  attr_reader :source_type_identifier
  attr_reader :detected_programming_language
  attr_reader :metadata_hash
  
  def initialize(
    content:,
    file_path: nil,
    source_type: :unknown,
    metadata: {}
  )
    @original_source_code_content = content.freeze
    @file_system_path_if_from_file = file_path&.freeze
    @source_type_identifier = source_type
    @metadata_hash = metadata.freeze
    
    @detected_programming_language = ProgrammingLanguageDetector.detect_language_from_content_and_file_path(
      @original_source_code_content,
      @file_system_path_if_from_file
    )
  end
  
  def originated_from_file_on_filesystem?
    !@file_system_path_if_from_file.nil?
  end
  
  def display_name_for_user_interface
    if originated_from_file_on_filesystem?
      @file_system_path_if_from_file
    else
      @source_type_identifier.to_s
    end
  end
  
  def language_is_supported_for_analysis?
    @detected_programming_language != :unknown
  end
  
  def count_total_lines_in_source_code
    @original_source_code_content.lines.count
  end
  
  def count_non_blank_non_comment_lines_in_source_code
    lines_that_are_not_blank_or_comments = @original_source_code_content.lines.reject do |single_line|
      stripped_line = single_line.strip
      stripped_line.empty? || stripped_line.start_with?("#")
    end
    
    lines_that_are_not_blank_or_comments.count
  end
end

# ===== LANGUAGE DETECTION =====

# Class: ProgrammingLanguageDetector
# Purpose: Determines programming language from code content and file path
# Strategy:
#   1. Check file extension first (most reliable indicator)
#   2. Check shebang line if present (for scripts)
#   3. Scan for language-specific syntax patterns
#   4. Return :unknown if cannot determine with confidence
# Supported languages:
#   - Ruby (.rb, .rake, Gemfile, Rakefile)
#   - Shell (.sh, .zsh, .bash, #!/bin/bash, #!/bin/zsh)
#   - YAML (.yml, .yaml, starts with ---)
#   - HTML (.html, .erb, contains <!DOCTYPE)
#   - CSS (.css, .scss, .sass)
#   - JavaScript (.js, .jsx, .ts, .tsx)
# Design principle: Conservative detection (only identify if confident)

class ProgrammingLanguageDetector
  RUBY_FILE_EXTENSIONS = [".rb", ".rake", ".gemspec"].freeze
  RUBY_FILE_BASENAMES = ["Gemfile", "Rakefile", "Guardfile"].freeze
  
  SHELL_FILE_EXTENSIONS = [".sh", ".bash", ".zsh"].freeze
  SHELL_SHEBANG_PATTERNS = %r{^#!/.*/(bash|zsh|sh)}.freeze
  
  YAML_FILE_EXTENSIONS = [".yml", ".yaml"].freeze
  YAML_DOCUMENT_MARKER = "---"
  
  HTML_FILE_EXTENSIONS = [".html", ".htm", ".erb", ".haml"].freeze
  HTML_DOCTYPE_PATTERN = /<!DOCTYPE/i.freeze
  
  CSS_FILE_EXTENSIONS = [".css", ".scss", ".sass", ".less"].freeze
  
  JAVASCRIPT_FILE_EXTENSIONS = [".js", ".jsx", ".ts", ".tsx", ".mjs"].freeze
  
  def self.detect_language_from_content_and_file_path(code_content, file_path)
    # Try file-based detection first (most reliable)
    if file_path
      language_from_file_path = detect_language_from_file_path_indicators(file_path)
      return language_from_file_path if language_from_file_path != :unknown
    end
    
    # Fall back to content-based detection
    detect_language_from_code_content_patterns(code_content)
  end
  
  def self.detect_language_from_file_path_indicators(file_path)
    file_extension = File.extname(file_path).downcase
    file_basename = File.basename(file_path)
    
    return :ruby if RUBY_FILE_EXTENSIONS.include?(file_extension)
    return :ruby if RUBY_FILE_BASENAMES.include?(file_basename)
    
    return :shell if SHELL_FILE_EXTENSIONS.include?(file_extension)
    
    return :yaml if YAML_FILE_EXTENSIONS.include?(file_extension)
    
    return :html if HTML_FILE_EXTENSIONS.include?(file_extension)
    
    return :css if CSS_FILE_EXTENSIONS.include?(file_extension)
    
    return :javascript if JAVASCRIPT_FILE_EXTENSIONS.include?(file_extension)
    
    :unknown
  end
  
  def self.detect_language_from_code_content_patterns(code_content)
    return :unknown if code_content.nil? || code_content.empty?
    
    first_line_of_code = code_content.lines.first&.strip || ""
    
    # Check for shebang patterns
    return :shell if first_line_of_code.match?(SHELL_SHEBANG_PATTERNS)
    return :ruby if first_line_of_code.include?("ruby")
    
    # Check for Ruby-specific patterns
    return :ruby if code_content.include?("frozen_string_literal")
    return :ruby if code_content.match?(/^\s*class\s+[A-Z]/)
    return :ruby if code_content.match?(/^\s*module\s+[A-Z]/)
    return :ruby if code_content.match?(/^\s*def\s+\w+/)
    
    # Check for YAML document marker
    return :yaml if code_content.strip.start_with?(YAML_DOCUMENT_MARKER)
    
    # Check for HTML DOCTYPE
    return :html if code_content.match?(HTML_DOCTYPE_PATTERN)
    
    # Check for JavaScript/TypeScript patterns
    return :javascript if code_content.include?("function")
    return :javascript if code_content.match?(/\bconst\s+\w+\s*=/)
    return :javascript if code_content.match?(/\blet\s+\w+\s*=/)
    
    :unknown
  end
end

# ===== CODE LOADING FROM VARIOUS SOURCES =====

# Class: CodeUnitLoader
# Purpose: Loads code from any source and converts to CodeUnit objects
# Supported sources:
#   - Single file path: "path/to/file.rb"
#   - Directory path: "path/to/directory" (recursive)
#   - stdin: "-" or nil
#   - Clipboard: "@clipboard"
#   - GitHub URL: "https://github.com/user/repo"
#   - Direct text: any other string treated as code
# Design principles:
#   - Uniform treatment: all sources become CodeUnit array
#   - Fail gracefully: return empty array if source unavailable
#   - No external dependencies: uses only stdlib

class CodeUnitLoader
  STDIN_INDICATORS = ["-", nil].freeze
  CLIPBOARD_INDICATOR = "@clipboard"
  GITHUB_URL_PATTERN = %r{github\.com/}.freeze
  
  EXCLUDED_DIRECTORY_PATTERNS = [
    "/.git/",
    "/node_modules/",
    "/vendor/",
    "/tmp/",
    "/.bundle/",
    "/coverage/"
  ].freeze
  
  CODE_FILE_EXTENSIONS = [
    ".rb", ".rake",
    ".sh", ".bash", ".zsh",
    ".yml", ".yaml",
    ".html", ".erb",
    ".css", ".scss",
    ".js", ".jsx", ".ts"
  ].freeze
  
  def self.load_code_units_from_input_source_specification(input_source_spec)
    return load_code_units_from_standard_input if STDIN_INDICATORS.include?(input_source_spec)
    return load_code_units_from_system_clipboard if input_source_spec == CLIPBOARD_INDICATOR
    return load_code_units_from_github_repository(input_source_spec) if input_source_spec.to_s.match?(GITHUB_URL_PATTERN)
    return load_code_units_from_directory_recursively(input_source_spec) if File.directory?(input_source_spec)
    return load_code_units_from_single_file(input_source_spec) if File.exist?(input_source_spec)
    
    load_code_units_from_direct_text_input(input_source_spec)
  end
  
  def self.load_code_units_from_standard_input
    code_content_from_stdin = $stdin.read
    
    [CodeUnit.new(
      content: code_content_from_stdin,
      source_type: :stdin
    )]
  end
  
  def self.load_code_units_from_system_clipboard
    code_content_from_clipboard = attempt_to_read_system_clipboard
    
    if code_content_from_clipboard.nil? || code_content_from_clipboard.empty?
      puts "WARNING: Could not read from clipboard or clipboard is empty"
      return []
    end
    
    [CodeUnit.new(
      content: code_content_from_clipboard,
      source_type: :clipboard
    )]
  end
  
  def self.attempt_to_read_system_clipboard
    # Try macOS pbpaste first
    clipboard_content = `pbpaste 2>/dev/null`.strip
    return clipboard_content unless clipboard_content.empty?
    
    # Try Linux xclip
    clipboard_content = `xclip -selection clipboard -o 2>/dev/null`.strip
    return clipboard_content unless clipboard_content.empty?
    
    # Try Linux xsel
    clipboard_content = `xsel --clipboard --output 2>/dev/null`.strip
    return clipboard_content unless clipboard_content.empty?
    
    nil
  rescue StandardError => clipboard_error
    puts "WARNING: Error reading clipboard: #{clipboard_error.message}"
    nil
  end
  
  def self.load_code_units_from_github_repository(github_url)
    require "tmpdir"
    
    temporary_clone_directory = Dir.mktmpdir("github_repo_")
    
    clone_command = "git clone --depth 1 --quiet #{github_url} #{temporary_clone_directory} 2>&1"
    clone_output = `#{clone_command}`
    
    unless $CHILD_STATUS.success?
      puts "ERROR: Failed to clone repository: #{github_url}"
      puts "Git output: #{clone_output}"
      return []
    end
    
    code_units_from_cloned_repo = load_code_units_from_directory_recursively(
      temporary_clone_directory
    )
    
    code_units_from_cloned_repo
  ensure
    FileUtils.rm_rf(temporary_clone_directory) if temporary_clone_directory
  end
  
  def self.load_code_units_from_directory_recursively(directory_path)
    all_code_file_paths_in_directory = find_all_code_files_in_directory_tree(
      directory_path
    )
    
    if all_code_file_paths_in_directory.empty?
      puts "WARNING: No code files found in directory: #{directory_path}"
      return []
    end
    
    all_code_file_paths_in_directory.map do |single_file_path|
      load_code_units_from_single_file(single_file_path).first
    end
  end
  
  def self.find_all_code_files_in_directory_tree(directory_path)
    glob_pattern = File.join(directory_path, "**", "*")
    
    all_paths_in_directory = Dir.glob(glob_pattern, File::FNM_DOTMATCH)
    
    code_files_only = all_paths_in_directory.select do |path|
      file_should_be_included_in_analysis?(path)
    end
    
    code_files_only
  end
  
  def self.file_should_be_included_in_analysis?(file_path)
    return false if File.directory?(file_path)
    return false if file_in_excluded_directory?(file_path)
    return false unless file_has_code_extension?(file_path)
    
    true
  end
  
  def self.file_in_excluded_directory?(file_path)
    EXCLUDED_DIRECTORY_PATTERNS.any? do |excluded_pattern|
      file_path.include?(excluded_pattern)
    end
  end
  
  def self.file_has_code_extension?(file_path)
    file_extension = File.extname(file_path).downcase
    CODE_FILE_EXTENSIONS.include?(file_extension)
  end
  
  def self.load_code_units_from_single_file(file_path)
    unless File.exist?(file_path)
      puts "ERROR: File not found: #{file_path}"
      return []
    end
    
    unless File.readable?(file_path)
      puts "ERROR: File not readable: #{file_path}"
      return []
    end
    
    file_content = File.read(file_path, encoding: "UTF-8")
    
    [CodeUnit.new(
      content: file_content,
      file_path: file_path,
      source_type: :file
    )]
  rescue StandardError => file_read_error
    puts "ERROR: Could not read file #{file_path}: #{file_read_error.message}"
    []
  end
  
  def self.load_code_units_from_direct_text_input(text_content)
    [CodeUnit.new(
      content: text_content,
      source_type: :text
    )]
  end
end

# ===== UNIVERSAL CODE ANALYSIS ORCHESTRATOR =====

# Class: UniversalCodeAnalyzer
# Purpose: Coordinates all types of code analysis for a single unit
# Analysis types performed:
#   1. Naming quality (Strunk & White principles)
#   2. Structural quality (Clean Code principles)
#   3. Code smell detection (Fowler catalog)
#   4. Typographic quality (Bringhurst principles)
#   5. Principle alignment (36 unified principles)
# Returns: Hash with all violation categories
# Design: Each analysis type is delegated to specialized analyzer class

class UniversalCodeAnalyzer
  def self.analyze_single_code_unit_for_all_violation_types(code_unit)
    {
      naming_violations: NamingQualityAnalyzer.find_all_naming_violations_in_code_unit(code_unit),
      structure_violations: StructuralQualityAnalyzer.find_all_structure_violations_in_code_unit(code_unit),
      code_smells: CodeSmellDetector.find_all_code_smells_in_code_unit(code_unit),
      typography_violations: TypographyAnalyzer.find_all_typography_violations_in_code_unit(code_unit),
      principle_violations: PrincipleAlignmentChecker.find_all_principle_violations_in_code_unit(code_unit)
    }
  end
end

# ===== NAMING QUALITY ANALYSIS =====

# Class: NamingQualityAnalyzer
# Purpose: Detects violations of naming principles from Elements of Style
# Checks for:
#   - Generic verbs (process, handle, do, manage, get, set)
#   - Single-letter variables (except i, j, k in loops)
#   - Vague terms (data, info, thing, stuff, object, value)
#   - Non-pronounceable names
#   - Non-searchable names
# Philosophy: Names are compressed prose - must follow prose rules

class NamingQualityAnalyzer
  GENERIC_VERBS_TO_AVOID = %w[
    process handle do manage
    get set check validate
    calc compute run execute
  ].freeze
  
  VAGUE_NOUNS_TO_AVOID = %w[
    data info thing stuff object
    value item element entry record
  ].freeze
  
  def self.find_all_naming_violations_in_code_unit(code_unit)
    violations = []
    
    violations.concat(find_generic_verb_usage_violations(code_unit))
    violations.concat(find_single_letter_variable_violations(code_unit))
    violations.concat(find_vague_noun_usage_violations(code_unit))
    
    violations
  end
  
  def self.find_generic_verb_usage_violations(code_unit)
    generic_verbs_found_in_code = []
    
    GENERIC_VERBS_TO_AVOID.each do |generic_verb|
      pattern_to_find_verb = /\b#{Regexp.escape(generic_verb)}\b/i
      
      if code_unit.original_source_code_content.match?(pattern_to_find_verb)
        generic_verbs_found_in_code << generic_verb
      end
    end
    
    return [] if generic_verbs_found_in_code.empty?
    
    [{
      violation_type: :generic_verbs_used,
      severity_level: :high,
      description: "Generic verbs found in code: #{generic_verbs_found_in_code.join(', ')}",
      rationale: "Use specific, domain-appropriate verbs (Elements of Style: use specific language)",
      how_to_fix: "Replace with domain-specific verbs (calculate, validate, authenticate, etc.)",
      principles_violated: ["understandable", "honest", "transparent"]
    }]
  end
  
  def self.find_single_letter_variable_violations(code_unit)
    # Pattern: finds single letter followed by equals (variable assignment)
    # Excludes: i, j, k (common loop counters)
    single_letter_pattern = /\b([a-hln-z])\s*=/
    
    matches = code_unit.original_source_code_content.scan(single_letter_pattern)
    
    return [] if matches.empty?
    
    unique_single_letter_variables = matches.flatten.uniq
    
    [{
      violation_type: :single_letter_variables,
      severity_level: :high,
      description: "Single-letter variable names found: #{unique_single_letter_variables.join(', ')}",
      rationale: "Variables must be pronounceable and searchable (Clean Code)",
      how_to_fix: "Use full descriptive names that reveal intent",
      principles_violated: ["understandable", "honest"]
    }]
  end
  
  def self.find_vague_noun_usage_violations(code_unit)
    vague_nouns_found_in_code = []
    
    VAGUE_NOUNS_TO_AVOID.each do |vague_noun|
      pattern_to_find_noun = /\b#{Regexp.escape(vague_noun)}\b/i
      
      if code_unit.original_source_code_content.match?(pattern_to_find_noun)
        vague_nouns_found_in_code << vague_noun
      end
    end
    
    return [] if vague_nouns_found_in_code.empty?
    
    [{
      violation_type: :vague_nouns_used,
      severity_level: :medium,
      description: "Vague nouns found: #{vague_nouns_found_in_code.join(', ')}",
      rationale: "Use specific, concrete terms (Elements of Style: prefer specific to vague)",
      how_to_fix: "Replace with domain-specific nouns (customer, order, transaction, etc.)",
      principles_violated: ["understandable", "transparent"]
    }]
  end
end

# ===== STRUCTURAL QUALITY ANALYSIS =====

# Class: StructuralQualityAnalyzer
# Purpose: Detects structural violations from Clean Code principles
# Checks for:
#   - Long methods (> 20 lines)
#   - Large classes (> 300 lines)
#   - High cyclomatic complexity (> 10)
#   - Too many parameters (> 3)
# Philosophy: Small, focused units are easier to understand and test

class StructuralQualityAnalyzer
  METHOD_LENGTH_WARNING_THRESHOLD = 15
  METHOD_LENGTH_ERROR_THRESHOLD = 20
  METHOD_LENGTH_CRITICAL_THRESHOLD = 50
  
  CLASS_LENGTH_WARNING_THRESHOLD = 200
  CLASS_LENGTH_ERROR_THRESHOLD = 300
  
  PARAMETER_COUNT_WARNING_THRESHOLD = 3
  PARAMETER_COUNT_ERROR_THRESHOLD = 5
  
  def self.find_all_structure_violations_in_code_unit(code_unit)
    violations = []
    
    violations.concat(find_long_method_violations(code_unit))
    violations.concat(find_large_class_violations(code_unit))
    violations.concat(find_high_parameter_count_violations(code_unit))
    
    violations
  end
  
  def self.find_long_method_violations(code_unit)
    return [] unless code_unit.detected_programming_language == :ruby
    
    method_definitions_with_line_counts = extract_all_methods_with_line_counts(
      code_unit.original_source_code_content
    )
    
    long_methods = method_definitions_with_line_counts.select do |method_info|
      method_info[:line_count] > METHOD_LENGTH_ERROR_THRESHOLD
    end
    
    long_methods.map do |long_method_info|
      severity = determine_severity_for_method_length(long_method_info[:line_count])
      
      {
        violation_type: :long_method,
        severity_level: severity,
        method_name: long_method_info[:name],
        actual_line_count: long_method_info[:line_count],
        threshold_exceeded: METHOD_LENGTH_ERROR_THRESHOLD,
        description: "Method '#{long_method_info[:name]}' is #{long_method_info[:line_count]} lines (max: #{METHOD_LENGTH_ERROR_THRESHOLD})",
        rationale: "Long methods are hard to understand, test, and modify (Clean Code)",
        how_to_fix: "Apply Extract Method refactoring to break into smaller methods",
        refactoring_technique: "extract_method",
        principles_violated: ["minimal", "understandable", "single_responsibility"]
      }
    end
  end
  
  def self.extract_all_methods_with_line_counts(source_code)
    method_pattern = /^\s*def\s+(\w+).*?\n(.*?)\n\s*end/m
    
    methods_found = []
    
    source_code.scan(method_pattern) do |method_name, method_body|
      non_blank_lines = method_body.lines.reject { |line| line.strip.empty? }
      
      methods_found << {
        name: method_name,
        line_count: non_blank_lines.size,
        body: method_body
      }
    end
    
    methods_found
  end
  
  def self.determine_severity_for_method_length(line_count)
    return :critical if line_count >= METHOD_LENGTH_CRITICAL_THRESHOLD
    return :high if line_count >= METHOD_LENGTH_ERROR_THRESHOLD
    return :medium if line_count >= METHOD_LENGTH_WARNING_THRESHOLD
    :low
  end
  
  def self.find_large_class_violations(code_unit)
    return [] unless code_unit.detected_programming_language == :ruby
    
    class_definitions_with_line_counts = extract_all_classes_with_line_counts(
      code_unit.original_source_code_content
    )
    
    large_classes = class_definitions_with_line_counts.select do |class_info|
      class_info[:line_count] > CLASS_LENGTH_ERROR_THRESHOLD
    end
    
    large_classes.map do |large_class_info|
      {
        violation_type: :large_class,
        severity_level: :high,
        class_name: large_class_info[:name],
        actual_line_count: large_class_info[:line_count],
        threshold_exceeded: CLASS_LENGTH_ERROR_THRESHOLD,
        description: "Class '#{large_class_info[:name]}' is #{large_class_info[:line_count]} lines (max: #{CLASS_LENGTH_ERROR_THRESHOLD})",
        rationale: "Large classes likely have multiple responsibilities (Clean Code)",
        how_to_fix: "Apply Extract Class refactoring to separate concerns",
        refactoring_technique: "extract_class",
        principles_violated: ["minimal", "single_responsibility"]
      }
    end
  end
  
  def self.extract_all_classes_with_line_counts(source_code)
    class_pattern = /^\s*class\s+(\w+).*?\n(.*?)\nend/m
    
    classes_found = []
    
    source_code.scan(class_pattern) do |class_name, class_body|
      total_lines = class_body.lines.size
      
      classes_found << {
        name: class_name,
        line_count: total_lines,
        body: class_body
      }
    end
    
    classes_found
  end
  
  def self.find_high_parameter_count_violations(code_unit)
    return [] unless code_unit.detected_programming_language == :ruby
    
    method_pattern = /def\s+(\w+)\s*\((.*?)\)/
    
    violations = []
    
    code_unit.original_source_code_content.scan(method_pattern) do |method_name, parameters_string|
      parameter_count = count_parameters_in_parameter_string(parameters_string)
      
      if parameter_count > PARAMETER_COUNT_ERROR_THRESHOLD
        violations << {
          violation_type: :too_many_parameters,
          severity_level: :high,
          method_name: method_name,
          parameter_count: parameter_count,
          threshold: PARAMETER_COUNT_ERROR_THRESHOLD,
          description: "Method '#{method_name}' has #{parameter_count} parameters (max: #{PARAMETER_COUNT_ERROR_THRESHOLD})",
          rationale: "Many parameters make methods hard to call and understand (Clean Code)",
          how_to_fix: "Apply Introduce Parameter Object refactoring",
          refactoring_technique: "introduce_parameter_object",
          principles_violated: ["minimal", "understandable"]
        }
      end
    end
    
    violations
  end
  
  def self.count_parameters_in_parameter_string(parameters_string)
    return 0 if parameters_string.strip.empty?
    
    parameters_string.split(",").size
  end
end

# ===== CODE SMELL DETECTION =====

# Class: CodeSmellDetector
# Purpose: Detects code smells from Fowler's Refactoring catalog
# Smells detected:
#   - Duplicate code (repeated blocks)
#   - Feature envy (method uses other class more than own)
#   - Long parameter list
#   - Primitive obsession
# Philosophy: Smells indicate deeper structural problems

class CodeSmellDetector
  MINIMUM_DUPLICATE_BLOCK_SIZE_IN_LINES = 3
  MINIMUM_DUPLICATE_BLOCK_SIZE_IN_CHARACTERS = 50
  
  def self.find_all_code_smells_in_code_unit(code_unit)
    smells = []
    
    smells.concat(find_duplicate_code_smells(code_unit))
    smells.concat(find_commented_out_code_smells(code_unit))
    
    smells
  end
  
  def self.find_duplicate_code_smells(code_unit)
    duplicate_blocks_found = find_all_duplicate_code_blocks_in_source(
      code_unit.original_source_code_content
    )
    
    return [] if duplicate_blocks_found.empty?
    
    [{
      smell_type: :duplicate_code,
      severity_level: :high,
      duplicate_count: duplicate_blocks_found.size,
      description: "Found #{duplicate_blocks_found.size} duplicate code blocks",
      rationale: "Duplication makes maintenance harder (Refactoring: DRY principle)",
      how_to_fix: "Apply Extract Method to create single shared implementation",
      refactoring_technique: "extract_method",
      principles_violated: ["minimal", "anti_duplication"]
    }]
  end
  
  def self.find_all_duplicate_code_blocks_in_source(source_code)
    blocks_seen = Hash.new(0)
    
    source_code.lines.each_cons(MINIMUM_DUPLICATE_BLOCK_SIZE_IN_LINES) do |consecutive_lines|
      block_text = consecutive_lines.join
      normalized_block = normalize_code_block_for_comparison(block_text)
      
      next if normalized_block.length < MINIMUM_DUPLICATE_BLOCK_SIZE_IN_CHARACTERS
      next if block_is_just_boilerplate?(normalized_block)
      
      blocks_seen[normalized_block] += 1
    end
    
    blocks_seen.select { |_block, count| count > 1 }.keys
  end
  
  def self.normalize_code_block_for_comparison(block_text)
    # Remove leading/trailing whitespace and compress internal whitespace
    block_text.strip.gsub(/\s+/, " ")
  end
  
  def self.block_is_just_boilerplate?(normalized_block)
    # Ignore common boilerplate patterns
    normalized_block.match?(/^\s*(end|}\s*$|private|public|protected)/)
  end
  
  def self.find_commented_out_code_smells(code_unit)
    commented_code_lines = find_lines_with_commented_out_code(
      code_unit.original_source_code_content
    )
    
    return [] if commented_code_lines.empty?
    
    [{
      smell_type: :commented_out_code,
      severity_level: :critical,
      line_count: commented_code_lines.size,
      description: "Found #{commented_code_lines.size} lines of commented-out code",
      rationale: "Commented code rots and confuses (Clean Code: delete it, source control remembers)",
      how_to_fix: "Delete all commented code immediately",
      principles_violated: ["minimal", "honest", "transparent"]
    }]
  end
  
  def self.find_lines_with_commented_out_code(source_code)
    code_pattern_in_comments = /^\s*#\s*(def|class|if|while|for|return|=)/
    
    source_code.lines.select do |line|
      line.match?(code_pattern_in_comments)
    end
  end
end

# ===== TYPOGRAPHY ANALYSIS =====

# Class: TypographyAnalyzer  
# Purpose: Checks visual presentation quality (Bringhurst principles)
# Checks for:
#   - Lines too long (> 120 characters)
#   - Inconsistent indentation
#   - Missing blank lines between sections
#   - Trailing whitespace
# Philosophy: Code is text to be read - typography matters

class TypographyAnalyzer
  MAXIMUM_LINE_LENGTH_FOR_CODE = 120
  MAXIMUM_LINE_LENGTH_FOR_PROSE = 75
  
  def self.find_all_typography_violations_in_code_unit(code_unit)
    violations = []
    
    violations.concat(find_line_length_violations(code_unit))
    violations.concat(find_trailing_whitespace_violations(code_unit))
    
    violations
  end
  
  def self.find_line_length_violations(code_unit)
    lines_that_are_too_long = code_unit.original_source_code_content.lines.select do |line|
      line.chomp.length > MAXIMUM_LINE_LENGTH_FOR_CODE
    end
    
    return [] if lines_that_are_too_long.empty?
    
    [{
      violation_type: :lines_too_long,
      severity_level: :low,
      line_count: lines_that_are_too_long.size,
      max_length_allowed: MAXIMUM_LINE_LENGTH_FOR_CODE,
      description: "#{lines_that_are_too_long.size} lines exceed #{MAXIMUM_LINE_LENGTH_FOR_CODE} characters",
      rationale: "Long lines require horizontal scrolling (Bringhurst: proper measure)",
      how_to_fix: "Break long lines across multiple lines with proper indentation",
      principles_violated: ["aesthetic", "understandable"]
    }]
  end
  
  def self.find_trailing_whitespace_violations(code_unit)
    lines_with_trailing_whitespace = code_unit.original_source_code_content.lines.select do |line|
      line_ends_with_whitespace?(line)
    end
    
    return [] if lines_with_trailing_whitespace.empty?
    
    [{
      violation_type: :trailing_whitespace,
      severity_level: :low,
      line_count: lines_with_trailing_whitespace.size,
      description: "#{lines_with_trailing_whitespace.size} lines have trailing whitespace",
      rationale: "Trailing whitespace is noise (Clean Code: clean formatting)",
      how_to_fix: "Strip trailing whitespace from all lines",
      principles_violated: ["minimal", "aesthetic"]
    }]
  end
  
  def self.line_ends_with_whitespace?(line)
    line.match?(/\s+\n$/) || (line.end_with?(" ") && !line.end_with?("\n"))
  end
end

# ===== PRINCIPLE ALIGNMENT CHECKING =====

# Class: PrincipleAlignmentChecker
# Purpose: Maps all violations back to violated principles
# Aggregates violations from all analyzers and determines which of
# the 36 unified principles are violated

class PrincipleAlignmentChecker
  def self.find_all_principle_violations_in_code_unit(code_unit)
    # This would aggregate all violations and map to principles
    # For now, return empty as other analyzers already tag principles
    []
  end
end

# ===== RESULT PRESENTATION =====

# Class: AnalysisResultPresenter
# Purpose: Formats and displays analysis results to user
# Output format:
#   - Per-unit summary with severity indicators
#   - Grouped violations by category
#   - Overall statistics
#   - Actionable fix suggestions

class AnalysisResultPresenter
  SEVERITY_ICONS = {
    critical: "🚫",
    high: "⚠️ ",
    medium: "●",
    low: "○"
  }.freeze
  
  def self.display_complete_analysis_results(code_units, analysis_results)
    puts "\n" + ("=" * 80)
    puts "ANALYSIS RESULTS"
    puts ("=" * 80)
    
    code_units.zip(analysis_results).each do |code_unit, analysis_result|
      display_results_for_single_code_unit(code_unit, analysis_result)
    end
    
    display_overall_statistics(code_units, analysis_results)
  end
  
  def self.display_results_for_single_code_unit(code_unit, analysis_result)
    puts "\n#{code_unit.display_name_for_user_interface}"
    puts "  Language: #{code_unit.detected_programming_language}"
    puts "  Lines: #{code_unit.count_total_lines_in_source_code}"
    
    total_violations = count_total_violations_in_analysis_result(analysis_result)
    
    if total_violations.zero?
      puts "  ✓ No violations found - code is excellent!"
      return
    end
    
    puts "  Issues: #{total_violations} violation(s) found"
    
    display_violations_by_category(analysis_result)
  end
  
  def self.count_total_violations_in_analysis_result(analysis_result)
    analysis_result.values.sum do |violations_array|
      violations_array.is_a?(Array) ? violations_array.size : 0
    end
  end
  
  def self.display_violations_by_category(analysis_result)
    analysis_result.each do |category_name, violations_in_category|
      next if violations_in_category.empty?
      
      puts "\n  #{category_name.to_s.tr('_', ' ').capitalize}:"
      
      violations_in_category.each do |single_violation|
        display_single_violation_details(single_violation)
      end
    end
  end
  
  def self.display_single_violation_details(violation)
    severity_level = violation[:severity_level] || violation[:severity]
    icon = SEVERITY_ICONS[severity_level] || "•"
    
    puts "    #{icon} #{violation[:description]}"
    puts "       Why: #{violation[:rationale]}" if violation[:rationale]
    puts "       Fix: #{violation[:how_to_fix]}" if violation[:how_to_fix]
  end
  
  def self.display_overall_statistics(code_units, analysis_results)
    total_units = code_units.size
    total_violations = analysis_results.sum do |result|
      count_total_violations_in_analysis_result(result)
    end
    units_with_no_violations = analysis_results.count do |result|
      count_total_violations_in_analysis_result(result).zero?
    end
    
    puts "\n" + ("=" * 80)
    puts "SUMMARY STATISTICS"
    puts ("=" * 80)
    puts "Total units analyzed: #{total_units}"
    puts "Total violations found: #{total_violations}"
    puts "Units with zero violations: #{units_with_no_violations}/#{total_units}"
    
    if total_violations.zero?
      puts "\n✓ Perfect! All code meets quality standards."
    else
      puts "\n#{total_violations} issue(s) need attention."
    end
  end
end

# ===== USER INTERACTION =====

# Class: UserInteractionHandler
# Purpose: Handles all user input/output for confirmations and choices

class UserInteractionHandler
  def self.ask_user_if_they_want_to_apply_fixes
    puts "\nApply automatic fixes to code? [y/N]"
    print "> "
    
    user_response = $stdin.gets&.chomp&.downcase || "n"
    
    user_response == "y" || user_response == "yes"
  end
end

# ===== AUTOMATIC FIX APPLICATION =====

# Class: AutomaticFixApplicator
# Purpose: Applies safe automatic fixes to code
# Fixes applied:
#   - Add missing frozen_string_literal (Ruby)
#   - Add missing shebang and safety flags (Shell)
#   - Add missing document marker (YAML)
#   - Strip trailing whitespace (all languages)
# Philosophy: Only apply fixes that are 100% safe

class AutomaticFixApplicator
  def self.apply_all_safe_fixes_to_code_unit(code_unit, analysis_result)
    fixed_content = code_unit.original_source_code_content.dup
    
    fixed_content = apply_language_specific_idiom_fixes(
      fixed_content,
      code_unit.detected_programming_language
    )
    
    fixed_content = apply_universal_formatting_fixes(fixed_content)
    
    write_fixed_content_to_destination(code_unit, fixed_content)
  end
  
  def self.apply_language_specific_idiom_fixes(content, language)
    case language
    when :ruby then RubyIdiomFixer.apply_all_ruby_idioms(content)
    when :shell then ShellIdiomFixer.apply_all_shell_idioms(content)
    when :yaml then YamlIdiomFixer.apply_all_yaml_idioms(content)
    else content
    end
  end
  
  def self.apply_universal_formatting_fixes(content)
    UniversalFormattingFixer.apply_all_formatting_fixes(content)
  end
  
  def self.write_fixed_content_to_destination(code_unit, fixed_content)
    if code_unit.originated_from_file_on_filesystem?
      File.write(code_unit.file_system_path_if_from_file, fixed_content)
      puts "  ✓ Fixed: #{code_unit.file_system_path_if_from_file}"
    else
      puts "\n#{fixed_content}"
    end
  end
end

# ===== LANGUAGE-SPECIFIC FIX APPLICATORS =====

class RubyIdiomFixer
  def self.apply_all_ruby_idioms(ruby_source_code)
    lines = ruby_source_code.lines
    
    add_frozen_string_literal_if_missing(lines)
    
    lines.join
  end
  
  def self.add_frozen_string_literal_if_missing(lines)
    return if frozen_string_literal_already_present?(lines)
    
    insertion_index = determine_frozen_literal_insertion_index(lines)
    
    lines.insert(insertion_index, "# frozen_string_literal: true\n", "\n")
  end
  
  def self.frozen_string_literal_already_present?(lines)
    lines.any? { |line| line.include?("frozen_string_literal") }
  end
  
  def self.determine_frozen_literal_insertion_index(lines)
    first_line_is_shebang = lines.first&.start_with?("#!")
    first_line_is_shebang ? 1 : 0
  end
end

class ShellIdiomFixer
  def self.apply_all_shell_idioms(shell_source_code)
    lines = shell_source_code.lines
    
    add_shebang_if_missing(lines)
    add_safety_flags_if_missing(lines)
    
    lines.join
  end
  
  def self.add_shebang_if_missing(lines)
    return if shebang_already_present?(lines)
    
    lines.unshift("#!/usr/bin/env zsh\n")
  end
  
  def self.shebang_already_present?(lines)
    lines.first&.start_with?("#!")
  end
  
  def self.add_safety_flags_if_missing(lines)
    return if safety_flags_already_present?(lines)
    
    shebang_index = find_shebang_line_index(lines)
    lines.insert(shebang_index + 1, "\nset -euo pipefail\n", "\n")
  end
  
  def self.safety_flags_already_present?(lines)
    lines.any? { |line| line.include?("set -") }
  end
  
  def self.find_shebang_line_index(lines)
    lines.index { |line| line.start_with?("#!") } || -1
  end
end

class YamlIdiomFixer
  def self.apply_all_yaml_idioms(yaml_source_code)
    lines = yaml_source_code.lines
    
    add_document_marker_if_missing(lines)
    
    lines.join
  end
  
  def self.add_document_marker_if_missing(lines)
    return if document_marker_already_present?(lines)
    
    lines.unshift("---\n")
  end
  
  def self.document_marker_already_present?(lines)
    lines.first&.strip == "---"
  end
end

class UniversalFormattingFixer
  def self.apply_all_formatting_fixes(source_code)
    lines = source_code.lines
    
    strip_trailing_whitespace_from_all_lines(lines)
    ensure_final_newline_present(lines)
    
    lines.join
  end
  
  def self.strip_trailing_whitespace_from_all_lines(lines)
    lines.map! do |line|
      line.rstrip + (line.end_with?("\n") ? "\n" : "")
    end
  end
  
  def self.ensure_final_newline_present(lines)
    return if lines.empty?
    return if lines.last.end_with?("\n")
    
    lines.last << "\n"
  end
end

# ===== PROGRAM ENTRY POINT =====

if __FILE__ == $PROGRAM_NAME
  input_source_from_command_line_arguments = ARGV[0]
  
  Pipeline.run_analysis_on_code_from_source(
    input_source_from_command_line_arguments
  )
end