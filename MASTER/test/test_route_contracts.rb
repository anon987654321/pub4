# frozen_string_literal: true

require "minitest/autorun"
require_relative "../tools/rails/route_contracts"

class TestRouteContracts < Minitest::Test
  Response = Struct.new(:code, :headers, :body) do
    def [](name) = headers[name]
  end

  def html_response(body) = Response.new("200", { "Content-Type" => "text/html; charset=utf-8" }, body)

  PAGE = File.read(File.join(__dir__, "fixtures", "route_contracts", "post_page.html"))

  def test_a_page_records_title_heading_landmarks_and_forms_with_ids_normalised
    row = RouteContracts.describe(html_response(PAGE))
    assert_equal 200, row["status"]
    assert_equal "text/html", row["type"]
    assert_equal "Post N · brgen", row["title"]
    assert_equal "Hei Bergen", row["heading"]
    assert_equal %w[header nav main form], row["landmarks"]
    assert_equal ["/posts/N/comments"], row["forms"]
  end

  def test_a_byte_body_records_readable_utf8_text
    body = "<title>Kategorier — BSDports</title><h1>Åpne</h1>".b
    row = RouteContracts.describe(html_response(body))
    assert_equal Encoding::UTF_8, row["title"].encoding
    refute_includes YAML.dump(row), "!binary"
  end

  def test_a_redirect_records_its_target_path_only
    response = Response.new("302", { "Location" => "https://brgen.no/session/new?return=7" }, "")
    row = RouteContracts.describe(response)
    assert_equal({ "status" => 302, "type" => "", "location" => "/session/new?return=N" }, row)
  end

  def test_compare_names_each_changed_field_and_each_missing_path
    expected = { "/a" => { "status" => 200, "title" => "A" }, "/gone" => { "status" => 200 } }
    actual = { "/a" => { "status" => 200, "title" => "B" }, "/new" => { "status" => 404 } }
    assert_equal [
      ["/a", 'title: "A" -> "B"'],
      ["/gone", "missing from the target"],
      ["/new", "not in the recorded contract"],
    ], RouteContracts.compare(expected, actual)
  end

  def test_matching_contracts_have_no_differences
    same = { "/" => { "status" => 200, "landmarks" => %w[main] } }
    assert_empty RouteContracts.compare(same, same)
  end

  def test_paths_skip_dynamic_segments_and_framework_routes
    paths = RouteContracts.paths("bsdports")
    refute_empty paths
    assert paths.none? { |path| path.include?(":") || path.start_with?("/rails/") }
  end
end
