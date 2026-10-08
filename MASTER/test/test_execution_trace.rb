# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/execution_trace"

class TestExecutionTrace < Minitest::Test
  def test_reread_hashes_every_supplied_file
    Dir.mktmpdir("execution_trace") do |root|
      paths = %w[a.rb b.yml c.txt].map do |name|
        path = File.join(root, name)
        File.write(path, "#{name}\n")
        path
      end
      seen = []

      trace = Master::Fix::ExecutionTrace.new(
        root:,
        files: paths,
        digestor: ->(path) { seen << path; Digest::SHA256.file(path) },
        ruby_checker: ->(_path) {}
      )
      trace.send(:reread, paths, failures = [])

      assert_empty failures
      assert_equal paths.sort, seen.sort
    end
  end

  def test_scope_names_become_repository_relative_git_paths
    trace = Master::Fix::ExecutionTrace.new(root: "/tmp/pub4", scope: %w[MASTER RAILS OPENBSD STUDIO], ruby_checker: ->(_path) {})

    assert_equal [], trace.send(:scope_paths)
  end

  def test_single_absolute_scope_becomes_a_repository_relative_git_path
    trace = Master::Fix::ExecutionTrace.new(root: "/tmp/pub4", scope: ["/tmp/pub4/RAILS"], ruby_checker: ->(_path) {})

    assert_equal ["RAILS"], trace.send(:scope_paths)
  end

  def test_missing_boot_surface_and_configuration_is_a_failure
    Dir.mktmpdir("execution_trace") do |root|
      trace = Master::Fix::ExecutionTrace.new(root:, files: [], ruby_checker: ->(_path) {})
      result = trace.run

      refute result.clean?
      assert result.failures.any? { |failure| failure.include?("MASTER/bin/cli: missing") }
      assert result.failures.any? { |failure| failure.include?("MASTER/data/laws.yml: missing") }
    end
  end

  def test_live_graph_reports_missing_dependency_methods
    trace = Master::Fix::ExecutionTrace.new(
      root: Master::ROOT,
      files: [],
      dependencies: { scanner: Object.new, fix_loop: nil, deliberation: Object.new, bus: Object.new }
    )

    failures = []
    trace.send(:verify_live_graph, failures)

    assert_includes failures, "live_graph: fix_loop missing"
    assert failures.any? { |failure| failure.include?("scanner missing #scan") }
  end

  def test_canonical_boot_configuration_does_not_depend_on_workflow_yml
    refute_includes Master::Fix::ExecutionTrace::BOOT_CONFIG.keys, "MASTER/data/workflow.yml"
    assert_includes Master::Fix::ExecutionTrace::BOOT_CONFIG.keys, "MASTER/data/limits.yml"
    assert_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["MASTER/data/laws.yml"], "transformation_policy"
    assert_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["MASTER/data/laws.yml"], "ROBUSTNESS"
    refute_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["MASTER/data/laws.yml"], "zsh"
    refute_includes Master::Fix::ExecutionTrace::BOOT_CONFIG["MASTER/data/laws.yml"], "preserve_user_intent"
  end
  def test_wrapped_ruby_is_checked_after_the_safe_wrapper_repair
    Dir.mktmpdir("execution_trace_wrapper") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "<sub># frozen_string_literal: true\nVALUE = 1\n</sub>\n")

      result = Master::Fix::ExecutionTrace.new(root:, files: [path]).run

      refute result.failures.any? { |failure| failure.include?("syntax failed") }, result.failures.inspect
    end
  end

  def test_wrapped_ruby_is_checked_after_transport_unwrap
    Dir.mktmpdir("execution_trace_wrapper_fallback") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "<sub># frozen_string_literal: true\nVALUE = 1\n</sub>\n")

      result = Master::Fix::ExecutionTrace.new(
        root:,
        files: [path],
        ruby_checker: ->(candidate) { RubyVM::InstructionSequence.compile_file(candidate) },
      ).run

      refute result.failures.any? { |failure| failure.include?("syntax failed") }, result.failures.inspect
    end
  end

  def test_inline_transport_wrapper_is_unwrapped
    Dir.mktmpdir("execution_trace_inline_wrapper") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "VALUE = 1\n</sub>\n")

      result = Master::Fix::ExecutionTrace.new(
        root:,
        files: [path],
        ruby_checker: ->(candidate) { RubyVM::InstructionSequence.compile_file(candidate) },
      ).run

      refute result.failures.any? { |failure| failure.include?("syntax failed") }, result.failures.inspect
    end
  end

  def test_preflight_does_not_allow_ast_fixer_to_mask_syntax_damage
    Dir.mktmpdir("execution_trace_no_fix") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "def broken(\n  true\nend\n")

      candidate = Master::Fix::Scan::AstFixer::Result.new(
        path:,
        changed: true,
        transforms: [:repair],
        content: "def repaired; true; end\n",
      )

      Master::Fix::Scan::AstFixer.stub(:propose, candidate) do
        result = Master::Fix::ExecutionTrace.new(
          root:,
          files: [path],
          ruby_checker: ->(candidate_path) { RubyVM::InstructionSequence.compile_file(candidate_path) },
        ).run

        assert result.failures.any? { |failure| failure.include?("syntax failed") },
               result.failures.inspect
      end
    end
  end

end
