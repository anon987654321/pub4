# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/execution_trace"
require "fileutils"
require "yaml"

class TestExecutionTraceSnapshot < Minitest::Test
  def test_preflight_rejects_a_file_changed_during_syntax_validation
    Dir.mktmpdir("execution_trace_snapshot") do |root|
      path = File.join(root, "changing.rb")
      File.write(path, "VALUE = 1\n")

      trace = Master::Fix::ExecutionTrace.new(
        root:,
        files: [path],
        ruby_checker: ->(_candidate) { File.write(path, "VALUE = 2\n") },
      )
      result = trace.run

      assert result.failures.any? { |failure| failure.include?("changed during preflight") },
             result.failures.inspect
    end
  end

  def test_scoped_preflight_detects_a_boot_file_changed_after_starting_snapshot
    Dir.mktmpdir("execution_trace_boot_snapshot") do |root|
      target = File.join(root, "RAILS/brgen/target.rb")
      boot_path = File.join(root, "MASTER/lib/master.rb")
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.mkdir_p(File.dirname(boot_path))
      File.write(target, "VALUE = 1\n")
      File.write(boot_path, "# initial\n")

      Master::Fix::ExecutionTrace::BOOT_CHAIN.each do |relative|
        path = File.join(root, relative)
        next if path == boot_path

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "# fixture\n")
      end
      Master::Fix::ExecutionTrace::BOOT_CONFIG.each do |relative, required|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(required.each_with_object({}) { |key, data| data[key] = {} }))
      end

      trace = Master::Fix::ExecutionTrace.new(
        root:,
        files: [target],
        ruby_checker: ->(_candidate) { File.write(boot_path, "# changed\n") },
      )
      result = trace.run

      assert result.failures.any? do |failure|
        failure.include?("MASTER/lib/master.rb: changed during preflight")
      end, result.failures.inspect
    end
  end

  def test_preflight_rejects_a_file_added_after_inventory
    Dir.mktmpdir("execution_trace_inventory") do |root|
      assert system("git", "-C", root, "init", "-q", "--initial-branch=main")
      path = File.join(root, "changing.rb")
      File.write(path, "VALUE = 1\n")

      trace = Master::Fix::ExecutionTrace.new(
        root:,
        ruby_checker: ->(_candidate) { File.write(File.join(root, "late.rb"), "VALUE = 3\n") },
      )
      result = trace.run

      assert result.failures.any? { |failure| failure.include?("file inventory changed during preflight") },
             result.failures.inspect
    end
  end

  def test_preflight_does_not_compile_bytes_that_differ_from_the_fingerprint
    Dir.mktmpdir("execution_trace_read_race") do |root|
      path = File.join(root, "changing.rb")
      File.write(path, "VALUE = 1\n")
      changed = false
      checker_calls = 0

      digestor = lambda do |candidate|
        digest = Digest::SHA256.file(candidate)
        if candidate == path && !changed
          changed = true
          File.write(candidate, "VALUE = 2\n")
        end
        digest
      end
      trace = Master::Fix::ExecutionTrace.new(
        root:,
        files: [path],
        digestor:,
        ruby_checker: ->(candidate) { checker_calls += 1; RubyVM::InstructionSequence.compile_file(candidate) },
      )

      result = trace.run

      assert_equal 0, checker_calls
      mismatch = result.failures.find do |failure|
        failure.include?("content differs during syntax validation")
      end
      assert mismatch, result.failures.inspect
    end
  end

  def test_configuration_validation_parses_only_the_fingerprinted_content
    Dir.mktmpdir("execution_trace_config_race") do |root|
      paths = Master::Fix::ExecutionTrace::BOOT_CONFIG.map do |relative, required|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(required.each_with_object({}) { |key, data| data[key] = {} }))
        path
      end
      laws_path = File.join(root, "MASTER/data/laws.yml")
      changed = false
      digestor = lambda do |path|
        digest = Digest::SHA256.file(path)
        if path == laws_path && !changed
          changed = true
          File.write(path, YAML.dump("ROBUSTNESS" => {}))
        end
        digest
      end
      trace = Master::Fix::ExecutionTrace.new(root:, files: paths, digestor:)
      failures = []
      trace.send(:reread, paths, failures)

      trace.send(:verify_configuration, failures)

      mismatch = failures.find do |failure|
        failure.include?("MASTER/data/laws.yml: content differs during configuration validation")
      end
      assert mismatch, failures.inspect
    end
  end

  def test_configuration_validation_rejects_false_yaml_roots
    Dir.mktmpdir("execution_trace_false_yaml") do |root|
      paths = Master::Fix::ExecutionTrace::BOOT_CONFIG.map do |relative, required|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        content = if relative == "MASTER/data/patterns.yml"
                    "false\n"
                  else
                    YAML.dump(required.each_with_object({}) { |key, data| data[key] = {} })
                  end
        File.write(path, content)
        path
      end
      trace = Master::Fix::ExecutionTrace.new(root:, files: paths)
      failures = []
      trace.send(:reread, paths, failures)

      trace.send(:verify_configuration, failures)

      assert_includes failures, "MASTER/data/patterns.yml: expected a hash"
    end
  end

  def test_preflight_reports_tracked_files_missing_from_disk
    Dir.mktmpdir("execution_trace_missing_file") do |root|
      assert system("git", "-C", root, "init", "-q", "--initial-branch=main")
      path = File.join(root, "missing.rb")
      File.write(path, "VALUE = 1\n")
      assert system("git", "-C", root, "add", "missing.rb")
      File.delete(path)

      trace = Master::Fix::ExecutionTrace.new(root:)
      files = trace.send(:file_list)
      failures = []
      trace.send(:reread, files, failures)

      assert_includes files, path
      assert failures.any? { |failure| failure.include?("missing.rb: reread failed") },
             failures.inspect
    end
  end
end
