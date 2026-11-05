# frozen_string_literal: true

require "minitest/autorun"
require_relative "../tools/rails/route_contracts"

class TestRouteContracts < Minitest::Test
  Response = Struct.new(:code, :headers, :body) do
    def [](name) = headers[name]
  end

  # minitest/mock is not installed here; swap the module function for the block.
  def with_fetch(fake)
    original = RouteContracts.method(:fetch)
    RouteContracts.define_singleton_method(:fetch) { |*args| fake.call(*args) }
    yield
  ensure
    RouteContracts.define_singleton_method(:fetch, original)
  end

  def html_response(body) = Response.new("200", { "Content-Type" => "text/html; charset=utf-8" }, body)

  PAGE = File.read(File.join(__dir__, "fixtures", "post_page.html"))

  def test_a_page_records_title_heading_landmarks_and_forms_with_ids_normalised
    row = RouteContracts.describe(html_response(PAGE))
    assert_equal 200, row["status"]
    assert_equal "text/html", row["type"]
    assert_equal "Post N - brgen", row["title"]
    assert_equal "Hei Bergen", row["heading"]
    assert_equal %w[header nav main form], row["landmarks"]
    assert_equal ["/posts/N/comments"], row["forms"]
  end

  def test_a_byte_body_records_readable_utf8_text
    body = "<title>Kategorier - BSDports</title><h1>Åpne</h1>".b
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

  # brgen's verticals 404 on brgen.no and answer on their subdomain.
  def test_a_path_that_404s_on_the_primary_host_is_recorded_on_the_host_that_answers
    target = RouteContracts::Target.new(app: "brgen", base: "http://127.0.0.1:1", host: "brgen.no,markedsplass.brgen.no")
    answers = { "brgen.no" => "404", "markedsplass.brgen.no" => "200" }
    fake = ->(_target, _path, host) { html_response("<title>Marked</title>").tap { |r| r.code = answers.fetch(host) } }
    with_fetch(fake) do
      row = RouteContracts.answer(target, "/listings", nil)
      assert_equal 200, row["status"]
      assert_equal "markedsplass.brgen.no", row["host"]
      assert_equal 404, RouteContracts.answer(target, "/listings", "brgen.no")["status"], "a pinned host is asked alone"
    end
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
