# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/execution_trace"
require "fileutils"
require "yaml"

class TestExecutionTraceBoundaries < Minitest::Test
  def test_preflight_refuses_symlinks_that_resolve_outside_the_repository
    Dir.mktmpdir("execution_trace_root") do |root|
      Dir.mktmpdir("execution_trace_outside") do |outside|
        target = File.join(outside, "secret.rb")
        link = File.join(root, "outside.rb")
        File.write(target, "SECRET = true\n")
        File.symlink(target, link)
        digest_calls = 0
        trace = Master::Fix::ExecutionTrace.new(
          root:,
          files: [link],
          digestor: ->(path) { digest_calls += 1; Digest::SHA256.file(path) },
        )
        failures = []

        trace.send(:reread, [link], failures)

        assert failures.any? { |failure| failure.include?("path resolves outside repository") },
               failures.inspect
        assert_equal 0, digest_calls
      end
    end
  end

  def test_internal_symlinks_are_fingerprinted_as_links_not_compiled_twice
    Dir.mktmpdir("execution_trace_internal_link") do |root|
      target = File.join(root, "target.rb")
      link = File.join(root, "alias.rb")
      File.write(target, "VALUE = 1\n")
      File.symlink("target.rb", link)
      checker_calls = 0
      trace = Master::Fix::ExecutionTrace.new(
        root:,
        files: [target, link],
        ruby_checker: ->(_candidate) { checker_calls += 1 },
      )

      trace.run

      assert_equal 1, checker_calls
    end
  end

  def test_configuration_validation_does_not_read_an_external_symlink
    Dir.mktmpdir("execution_trace_config_root") do |root|
      Dir.mktmpdir("execution_trace_config_outside") do |outside|
        target = File.join(outside, "laws.yml")
        link = File.join(root, "MASTER/data/laws.yml")
        FileUtils.mkdir_p(File.dirname(link))
        File.write(target, "CAPABILITY_STATUS_MUST_BE_TRUTHFUL: {}\n")
        File.symlink(target, link)
        calls = 0
        failures = []
        trace = Master::Fix::ExecutionTrace.new(root:, files: [])

        Master.stub(:parse_yaml_content, ->(*, **) { calls += 1; {} }) do
          trace.send(:configuration_body, "MASTER/data/laws.yml", link, failures)
        end

        assert_equal 0, calls
        assert failures.any? { |failure| failure.include?("path resolves outside repository") },
               failures.inspect
      end
    end
  end

  def test_scoped_preflight_tracks_configuration_files_outside_the_scope
    Dir.mktmpdir("execution_trace_scoped_config") do |root|
      paths = Master::Fix::ExecutionTrace::BOOT_CONFIG.map do |relative, required|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(required.each_with_object({}) { |key, data| data[key] = {} }))
        path
      end
      trace = Master::Fix::ExecutionTrace.new(root:, files: [])
      failures = []
      trace.send(:reread, [], failures)
      trace.send(:verify_configuration, failures)

      laws_path = File.join(root, "MASTER/data/laws.yml")
      File.write(laws_path, YAML.dump("ROBUSTNESS" => {}, "CAPABILITY_STATUS_MUST_BE_TRUTHFUL" => {}))
      trace.send(:verify_snapshot, trace.instance_variable_get(:@fingerprints).keys, failures)

      assert_includes trace.instance_variable_get(:@fingerprints).keys, laws_path
      assert failures.any? { |failure| failure.include?("laws.yml: changed during preflight") },
             failures.inspect
    end
  end

  def test_preflight_fingerprints_mandatory_boot_files_outside_the_scope
    Dir.mktmpdir("execution_trace_scoped_boot") do |root|
      Master::Fix::ExecutionTrace::BOOT_CHAIN.each do |relative|
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "# fixture\n")
      end
      trace = Master::Fix::ExecutionTrace.new(root:, files: [])
      failures = []
      trace.send(:reread, [], failures)
      trace.send(:verify_boot_surface, failures)

      entry = File.join(root, "MASTER/lib/master.rb")
      assert_includes trace.instance_variable_get(:@fingerprints).keys, entry
      assert_empty failures
    end
  end

  def test_canonical_yaml_reader_rejects_invalid_utf8
    Dir.mktmpdir("execution_trace_yaml_encoding") do |root|
      path = File.join(root, "invalid.yml")
      File.binwrite(path, [0xFF].pack("C"))

      error = assert_raises(EncodingError) { Master.read_yaml_content(path) }

      assert_match(/invalid UTF-8/, error.message)
    end
  end
end
