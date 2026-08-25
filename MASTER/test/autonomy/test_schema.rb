# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/autonomy"

class TestAutonomySchema < Minitest::Test
  # Through the same accessors the runtime uses, so what the checker asserts is
  # what the loop is handed. Passing a directory made this read the files a
  # second way, which is the drift the check exists to catch.
  def boot_documents
    { rules: Master.load_rules(root: Master::ROOT),
      autoload: Master.load_yaml(File.join(Master::DATA, "autoload.yml")) }
  end

  def test_repository_boot_configuration_has_a_valid_shape
    assert Master::Autonomy::Schema.validate_boot!(**boot_documents)
  end

  def test_a_missing_schema_key_is_refused
    error = assert_raises(RuntimeError) do
      Master::Autonomy::Schema.validate_boot!(rules: { "laws" => { "a" => 1 } }, autoload: { "autoload" => {} })
    end
    assert_match(/schema/, error.message)
  end

  def test_an_autoload_reason_naming_a_non_array_is_refused
    error = assert_raises(RuntimeError) do
      Master::Autonomy::Schema.validate_boot!(rules: { "schema" => 1, "laws" => { "a" => 1 } },
                                              autoload: { "autoload" => { "boot" => "lib/master.rb" } })
    end
    assert_match(/must be an array/, error.message)
  end
end
