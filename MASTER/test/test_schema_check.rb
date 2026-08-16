# frozen_string_literal: true

require_relative "test_helper"

class TestSchemaCheck < Minitest::Test
  def test_real_data_matches_expected_schemas
    assert_equal :clean, Master::Ground::SchemaCheck.verify!(root: Master::ROOT).value!
  end

  def test_missing_and_mismatched_files_are_reported
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "council.yml"), "schema: 2\n")
      result = Master::Ground::SchemaCheck.verify!(root:)

      assert result.err?
      assert_match(/council.yml: expected v1, found v2/, result.message)
      assert_match(/llm_output_rules.yml: expected v1, found \(missing\)/, result.message)
    end
  end
end
