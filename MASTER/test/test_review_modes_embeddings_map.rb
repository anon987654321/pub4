# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "net/http"

# Three review helpers with no test of their own: Modes wraps a message in the
# reasoning template for /reasoning, Embeddings is the optional Ollama vector
# path memory search uses when it is up, and RepoMap ranks files by PageRank
# over the code index's references to fit a token budget.
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
    _, err = capture_io { assert_equal "hi", modes.wrap("hi", mode: "rewoo") }
    assert_match(/wrap failed/, err)
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

  Sym = Struct.new(:fqn, :file, :type, :line)
  Ref = Struct.new(:from_file, :to_fqn)

  class Index
    def initialize(root)
      @symbols = {
        core: Sym.new("Core", File.join(root, "core.rb"), :class, 1),
        a: Sym.new("A", File.join(root, "a.rb"), :class, 1),
        b: Sym.new("B", File.join(root, "b.rb"), :class, 1),
      }
      @refs = [Ref.new(File.join(root, "a.rb"), "Core"), Ref.new(File.join(root, "b.rb"), "Core")]
    end

    def ready? = true
    def symbols = @symbols
    def references = @refs
    def symbols_in(path) = @symbols.values.select { |s| s.file == path }
  end

  def test_the_most_referenced_file_leads_the_map_and_the_budget_cuts_the_tail
    root = "/repo"
    full = Master::Review::RepoMap.new(code_index: Index.new(root), root:).render
    sections = full.lines.grep(/^## /).map(&:strip)

    assert_equal "## core.rb", sections.first
    assert_equal 3, sections.size

    tight = Master::Review::RepoMap.new(code_index: Index.new(root), root:, token_budget: 12).render
    assert_equal ["## core.rb"], tight.lines.grep(/^## /).map(&:strip)
  end

  def test_focus_pulls_its_file_ahead_of_rank
    root = "/repo"
    map = Master::Review::RepoMap.new(code_index: Index.new(root), root:).render(focus: ["a.rb"])

    assert_equal "## a.rb", map.lines.grep(/^## /).first.strip
  end
end
