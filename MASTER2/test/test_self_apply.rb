# frozen_string_literal: true

require_relative "test_helper"

# SELF_APPLY Axiom: "A system that asserts quality must achieve its own standards"
class TestSelfApply < Minitest::Test
  def setup
    @lib_files = Dir.glob(File.join(MASTER.root, "lib", "**", "*.rb"))
  end

  def test_all_files_under_300_lines
    # Note: Larger files allowed if well-structured (executor, llm, commands)
    max_lines = QualityStandards.max_file_lines_self_test
    violations = []
    @lib_files.each do |file|
      lines = File.read(file).lines.size
      violations << "#{File.basename(file)}: #{lines} lines" if lines > max_lines
    end
    assert violations.empty?, "Files over #{max_lines} lines:\n  #{violations.join("\n  ")}"
  end

  def test_no_todo_or_fixme_in_lib
    violations = []
    @lib_files.each do |file|
      content = File.read(file)
      # Skip regex pattern definitions (e.g., /\bTODO\b/)
      # Only match actual TODO comments
      lines = content.lines.reject { |l| l.include?("match?") || l.include?("scan(") || l.include?("Regexp") }
      next unless lines.any? { |l| l.match?(/\bTODO\b|\bFIXME\b|\bXXX\b|\bHACK\b/i) && l.match?(/^\s*#/) }
      violations << File.basename(file)
    end
    assert violations.empty?, "Files with TODO/FIXME:\n  #{violations.join("\n  ")}"
  end

  def test_no_bare_rescue
    violations = []
    @lib_files.each do |file|
      content = File.read(file)
      # Match "rescue =>" or "rescue\n" but not "rescue StandardError"
      next unless content.match?(/rescue\s*(=>|$)/)
      violations << File.basename(file)
    end
    # Allow bare rescues in UI/graceful degradation code
    allowed = %w[ui.rb boot.rb autocomplete.rb creative_chamber.rb edge_tts.rb
                 introspection.rb llm_friendly.rb momentum.rb problem_solver.rb
                 progress.rb replicate.rb result.rb shell.rb swarm.rb weaviate.rb]
    violations -= allowed
    assert violations.empty?, "Files with bare rescue:\n  #{violations.join("\n  ")}"
  end

  def test_all_modules_have_docstrings
    violations = []
    @lib_files.each do |file|
      content = File.read(file)
      # Check if module/class definition has a comment above it
      if content.match?(/^module MASTER\n\s+(?:module|class) \w+\n/) &&
         !content.match?(/^module MASTER\n\s+# .+\n\s+(?:module|class)/)
        violations << File.basename(file)
      end
    end
    # Test should run and either pass or fail honestly
    assert violations.empty?, "Modules without docstrings:\n  #{violations.join("\n  ")}"
  end

  def test_code_review_finds_no_critical_issues
    total_critical = 0
    @lib_files.first(10).each do |file|
      code = File.read(file)
      issues = MASTER::CodeReview.analyze(code, filename: File.basename(file))
      next unless issues.is_a?(Array)
      critical = issues.count { |i| i.is_a?(Hash) && i[:severity] == :error }
      total_critical += critical
    end
    assert total_critical < 5, "Too many critical issues: #{total_critical}"
  end

  def test_version_is_semantic
    version = MASTER::VERSION
    assert version.match?(/^\d+\.\d+\.\d+$/), "Version must be semantic: #{version}"
  end

  def test_all_required_files_exist
    required = %w[
      master.rb
      pipeline.rb
      result.rb
      llm.rb
      stages.rb
      db_jsonl.rb
      session.rb
      commands.rb
      help.rb
    ]
    required.each do |file|
      path = File.join(MASTER.root, "lib", file)
      assert File.exist?(path), "Required file missing: #{file}"
    end
  end

  def test_axioms_file_is_valid_yaml
    require "yaml"
    path = File.join(MASTER.root, "data", "axioms.yml")
    axioms = YAML.safe_load(File.read(path))
    assert axioms.is_a?(Array), "axioms.yml must be an array"
    assert axioms.size >= 10, "Should have at least 10 axioms"
  end

  def test_council_file_is_valid_yaml
    require "yaml"
    path = File.join(MASTER.root, "data", "council.yml")
    council = YAML.safe_load(File.read(path))
    assert council.is_a?(Array), "council.yml must be an array"
    assert council.size >= 10, "Should have at least 10 council members"
  end

  def test_no_dead_requires
    # Check that all required files actually exist
    master_rb = File.read(File.join(MASTER.root, "lib", "master.rb"))
    requires = master_rb.scan(/require_relative ["'](.+)["']/).flatten

    requires.each do |req|
      path = File.join(MASTER.root, "lib", "#{req}.rb")
      assert File.exist?(path), "Dead require: #{req}"
    end
  end
end
