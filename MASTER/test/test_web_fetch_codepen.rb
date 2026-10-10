# frozen_string_literal: true

require_relative "test_helper"

class TestWebFetchCodePen < Minitest::Test
  Fetch = Master::Io::WebFetch

  def fetch = Fetch.new(governor: Object.new)

  def test_all_failed_components_are_an_error_not_empty_success
    tool = fetch
    failure = ->(*) { Master::Result.err("offline", category: :infrastructure) }

    tool.stub(:fetch_one, failure) do
      result = tool.send(:fetch_codepen, "artist", "pen-id")

      refute result.ok?
      assert_match(/all components/, result.message)
    end
  end

  def test_partial_failure_is_disclosed_in_the_result
    tool = fetch
    response = lambda do |url, full: false|
      url.end_with?(".html") ? Master::Result.ok("<p>hello</p>") :
        Master::Result.err("component unavailable", category: :infrastructure)
    end

    tool.stub(:fetch_one, response) do
      result = tool.send(:fetch_codepen, "artist", "pen-id")

      assert result.ok?
      assert_includes result.value!, "<p>hello</p>"
      assert_includes result.value!, "Unavailable CodePen components: css, js"
    end
  end
end
