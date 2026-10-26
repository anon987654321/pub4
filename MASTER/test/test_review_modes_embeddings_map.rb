# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "net/http"

# Two review helpers with no test of their own: Modes wraps a message in the
# reasoning template for /reasoning, and Embeddings is the optional Ollama vector
# path memory search uses when it is up.
class TestReviewModesEmbeddingsMap < Minitest::Test
  def test_modes_wrap_with_the_selected_template_and_fall_back_to_direct
    root = Dir.mktmpdir("modes_")
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "prompts.yml"),
               "direct:\n  template: \"D: %{message}\"\nreact:\n  template: \"R: %{message}\"\nrewoo:\n  template: \"%{missing}\"\n")
    modes = Master::Review::Modes.new(root:)

    assert_equal "R: hi", modes.wrap("hi", mode: :react)
    assert_equal "D: hi", modes.wrap("hi", mode: "telepathy")
    assert_equal "hi", modes.wrap("hi", mode: "code_agent"), "a mode without a template passes the message through"
    # Dmesg status lines go to stdout, the same stream as every other unit line.
    out, = capture_io { assert_equal "hi", modes.wrap("hi", mode: "rewoo") }
    assert_match(/wrap failed/, out)
  ensure
    FileUtils.rm_rf(root)
  end

  def test_cosine_is_bounded_and_refuses_mismatched_vectors
    cosine = Master::Review::Embeddings.method(:cosine)

    assert_in_delta 1.0, cosine.call([1.0, 2.0], [2.0, 4.0])
    assert_in_delta(-1.0, cosine.call([1.0, 0.0], [-1.0, 0.0]))
    assert_equal 0.0, cosine.call([1.0], [1.0, 2.0])
    assert_equal 0.0, cosine.call([0.0, 0.0], [1.0, 1.0])
    assert_equal 0.0, cosine.call(nil, [1.0])
  end

  def test_embeddings_are_off_without_an_ollama_url
    previous = ENV.delete("OLLAMA_BASE_URL")

    refute Master::Review::Embeddings.enabled?
    assert_nil Master::Review::Embeddings.embed("anything")
  ensure
    ENV["OLLAMA_BASE_URL"] = previous if previous
  end

  # /api/embed takes `input` and answers `embeddings`, a list with one vector
  # per input; the superseded /api/embeddings took `prompt` and answered one.
  def test_embed_speaks_the_api_embed_contract
    reply = Net::HTTPOK.new("1.1", "200", "OK")
    reply.instance_variable_set(:@body, JSON.generate(embeddings: [[0.6, 0.8]]))
    reply.instance_variable_set(:@read, true)
    previous = ENV["OLLAMA_BASE_URL"]
    ENV["OLLAMA_BASE_URL"] = "http://127.0.0.1:9"

    http = FakeHTTP.new(reply)
    Net::HTTP.stub(:new, http) do
      assert_equal [0.6, 0.8], Master::Review::Embeddings.ollama_embed("a garment")
    end
    sent = http.sent
    assert_equal "/api/embed", sent.path
    assert_equal "a garment", JSON.parse(sent.body)["input"]
  ensure
    ENV["OLLAMA_BASE_URL"] = previous
  end

  class FakeHTTP
    attr_accessor :use_ssl, :read_timeout, :open_timeout
    attr_reader :sent

    def initialize(reply) = @reply = reply

    def request(request)
      @sent = request
      @reply
    end
  end
end
