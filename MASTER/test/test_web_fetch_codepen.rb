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

  def test_a_page_larger_than_the_text_limit_returns_its_first_text
    page = "<html><body>#{"<p>word </p>" * 4_000}</body></html>"
    response = Struct.new(:code, :body).new("200", page)
    result = fetch.send(:deliver, "https://example.test/", response)

    assert result.ok?
    assert_operator result.value!.bytesize, :<=, Fetch::MAX_BYTES + 200
    assert_includes result.value!, "word"
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

  # A response read whole before the size check let a large page into memory first.
  class Streamed
    attr_reader :code, :chunks_read

    def initialize(chunks)
      @code = "200"
      @chunks = chunks
      @chunks_read = 0
    end

    def read_body
      @chunks.each do |chunk|
        @chunks_read += 1
        yield chunk
      end
    end
  end

  def test_a_body_past_the_cap_is_refused_while_it_streams
    chunk = "x" * (1024 * 1024)
    response = Streamed.new(Array.new(10, chunk))

    assert_raises(Fetch::TooLarge) { fetch.send(:capped_body, response) }
    assert_equal 5, response.chunks_read, "reading stops at the first chunk over 4 MiB"
  end

  def test_a_body_under_the_cap_arrives_whole
    assert_equal "ab", fetch.send(:capped_body, Streamed.new(%w[a b]))
  end
end
