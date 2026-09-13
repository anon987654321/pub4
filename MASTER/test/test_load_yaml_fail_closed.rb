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

  # load_yaml remembers parses, so these two hold what the memo must not change:
  # a caller that mutates its hash cannot reach the next caller's, and an edit
  # to the file is read rather than served from memory.
  def test_each_call_gets_its_own_copy
    file = Tempfile.new(["memo", ".yml"])
    file.write("rules:\n  - id: one\n")
    file.flush
    first = Master.load_yaml(file.path)
    first["rules"] << { "id" => "mutated" }
    assert_equal [{ "id" => "one" }], Master.load_yaml(file.path)["rules"]
  ensure
    file.close!
  end

  def test_an_edit_is_read_again
    file = Tempfile.new(["memo", ".yml"])
    file.write("value: 1\n")
    file.flush
    assert_equal 1, Master.load_yaml(file.path)["value"]
    File.write(file.path, "value: 22\n")
    assert_equal 22, Master.load_yaml(file.path)["value"]
  ensure
    file.close!
  end
end
