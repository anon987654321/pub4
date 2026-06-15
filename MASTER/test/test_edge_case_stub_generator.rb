# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestEdgeCaseStubGenerator < Minitest::Test
  def test_generates_skipped_edge_case_stubs
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      source = File.join(dir, "lib", "sample_service.rb")
      File.write(source, "class SampleService; end\n")

      result = Master::Judge::Scan::EdgeCaseStubGenerator.new(root: dir).call("lib/sample_service.rb")

      assert result.ok?, result.message
      generated = File.join(dir, "test", "edge_cases", "test_sample_service_rb")
      assert File.exist?(generated)
      content = File.read(generated)
      assert_includes content, "test_nil_input"
      assert_includes content, "test_injection_attempt"
      assert_includes content, "skip \"wire SampleService API"
    end
  end
end
