# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/autonomy"

class TestAutonomySchema < Minitest::Test
  def test_repository_boot_configuration_has_a_valid_shape
    data_dir = File.expand_path("../../data", __dir__)
    assert Master::Autonomy::Schema.validate_boot!(data_dir)
  end
end
