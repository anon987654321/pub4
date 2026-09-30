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

  def test_missing_boot_surface_and_configuration_is_a_failure
    Dir.mktmpdir("execution_trace") do |root|
      trace = Master::Fix::ExecutionTrace.new(root:, files: [], ruby_checker: ->(_path) {})
      result = trace.run

      refute result.clean?
      assert result.failures.any? { |failure| failure.include?("MASTER/bin/cli: missing") }
      assert result.failures.any? { |failure| failure.include?("MASTER/data/rules.yml: missing") }
    end
  end

  def test_canonical_boot_configuration_does_not_depend_on_workflow_yml
    refute_includes Master::Fix::ExecutionTrace::BOOT_CONFIG, "MASTER/data/workflow.yml"
    assert_includes Master::Fix::ExecutionTrace::BOOT_CONFIG, "MASTER/data/limits.yml"
  end
end
