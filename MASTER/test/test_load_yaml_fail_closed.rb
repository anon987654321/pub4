# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class TestLoadYamlFailClosed < Minitest::Test
  def test_corrupt_yaml_raises_rather_than_returning_empty
    file = Tempfile.new(["broken", ".yml"])
    file.write("{ this is: [not: yaml")
    file.flush
    assert_raises(Psych::Exception) { Master.load_yaml(file.path) }
  ensure
    file.close!
  end

  def test_missing_file_still_returns_default
    assert_equal({}, Master.load_yaml("/no/such/path.yml"))
  end
end
