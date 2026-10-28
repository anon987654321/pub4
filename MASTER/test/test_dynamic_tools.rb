# frozen_string_literal: true

require_relative "test_helper"

class TestDynamicTools < Minitest::Test
  DYNAMIC_TOOLS = Master::Io::DynamicTools

  def valid_row(overrides = {})
    {
      "name" => "status_ping",
      "enabled" => true,
      "method" => "GET",
      "url" => "https://example.com/health",
      "elevated" => false,
      "description" => "Check an external service health endpoint"
    }.merge(overrides)
  end

  def with_catalogues(*documents)
    Dir.mktmpdir("dynamic-tool-catalogue") do |dir|
      paths = documents.each_with_index.map do |document, index|
        path = File.join(dir, "tools-#{index}.yml")
        File.write(path, document)
        path
      end
      DYNAMIC_TOOLS.stub(:paths, paths) { yield paths }
    end
  end

  def test_lookup_missing_returns_nil
    with_catalogues("# intentionally empty\n") do
      assert_nil DYNAMIC_TOOLS.lookup("nonexistent-tool-xyz")
    end
  end

  def test_comments_only_catalogue_is_a_valid_empty_inventory
    with_catalogues("# no dynamic endpoints are configured\n") do
      assert_empty DYNAMIC_TOOLS.load_definitions
    end
  end

  def test_non_list_catalogue_is_rejected_instead_of_becoming_empty
    with_catalogues(YAML.dump("name" => "status_ping")) do
      error = assert_raises(ArgumentError) { DYNAMIC_TOOLS.load_definitions }

      assert_match(/must be a YAML list/, error.message)
    end
  end

  def test_malformed_yaml_is_reported_with_the_source_path
    with_catalogues(":\n- [broken\n") do
      error = assert_raises(ArgumentError) { DYNAMIC_TOOLS.load_definitions }

      assert_match(/invalid YAML/, error.message)
      assert_includes error.message, "tools-0.yml"
    end
  end

  def test_unknown_fields_are_rejected
    with_catalogues(YAML.dump([valid_row("timout" => 2)])) do
      error = assert_raises(ArgumentError) { DYNAMIC_TOOLS.load_definitions }

      assert_match(/unknown field\(s\): timout/, error.message)
    end
  end

  def test_invalid_http_method_is_rejected
    with_catalogues(YAML.dump([valid_row("method" => "DELETE")])) do
      error = assert_raises(ArgumentError) { DYNAMIC_TOOLS.load_definitions }

      assert_match(/method must be one of GET, POST, PUT, PATCH/, error.message)
    end
  end

  def test_url_must_be_http_and_must_not_embed_credentials
    [
      valid_row("url" => "file:///etc/passwd"),
      valid_row("url" => "https://user:secret@example.com/"),
      valid_row("url" => "https://example.com/{broken")
    ].each do |row|
      with_catalogues(YAML.dump([row])) do
        assert_raises(ArgumentError) { DYNAMIC_TOOLS.load_definitions }
      end
    end
  end

  def test_enabled_and_elevated_must_be_booleans
    [["enabled", "false"], ["elevated", "false"]].each do |field, value|
      with_catalogues(YAML.dump([valid_row(field => value)])) do
        error = assert_raises(ArgumentError) { DYNAMIC_TOOLS.load_definitions }

        assert_match(/#{field} must be boolean/, error.message)
      end
    end
  end

  def test_duplicate_names_across_system_and_user_catalogues_are_rejected
    row = YAML.dump([valid_row])
    with_catalogues(row, row) do
      error = assert_raises(ArgumentError) { DYNAMIC_TOOLS.load_definitions }

      assert_match(/duplicate name\(s\): status_ping/, error.message)
    end
  end

  def test_disabled_valid_rows_remain_invisible_to_lookup
    with_catalogues(YAML.dump([valid_row("enabled" => false)])) do
      assert_empty DYNAMIC_TOOLS.load_definitions
      assert_nil DYNAMIC_TOOLS.lookup("status_ping")
    end
  end
end
