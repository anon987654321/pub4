# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"
require "fileutils"

class TestResearchSourceTools < Minitest::Test
  Governor = Struct.new(:answer, :asked) do
    def permit?(name, tier, detail)
      (self.asked ||= []) << [name, tier, detail]
      answer
    end
  end

  def allow = Governor.new(Master::Result.ok(true))

  def with_env(key, value)
    previous = ENV[key]
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
    yield
  ensure
    if previous.nil?
      ENV.delete(key)
    else
      ENV[key] = previous
    end
  end

  def with_stubbed_search(tool, value)
    fake = Object.new
    fake.define_singleton_method(:call) { |query:| value }
    tool.instance_variable_set(:@search, fake)
  end

  def test_lovdata_and_linguist_are_registered_in_the_shared_tool_map
    names = Master::Builder::DEFAULT_TOOL_MAP.keys
    assert_equal 1, names.count("Lovdata")
    assert_equal 1, names.count("Linguist")
    map = Master::Review::LLMDispatcher::LLM_TOOL_MAP
    assert_equal Master::Io::LLM::Lovdata, map.fetch(Master::Io::Lovdata)
    assert_equal Master::Io::LLM::Linguist, map.fetch(Master::Io::Linguist)
  end

  def test_lovdata_code_only_search_has_a_title_and_url_without_a_snippet
    tool = Master::Io::Lovdata.new(governor: allow)
    result = tool.call(reference: "LOV-2021-06-18-97", action: "search")

    assert result.ok?, result.to_s
    assert_includes result.value!, "LOV-2021-06-18-97"
    assert_includes result.value!, "https://lovdata.no/dokument/NL/lov/2021-06-18-97"
  end

  def test_lovdata_maps_official_law_codes_to_canonical_documents
    tool = Master::Io::Lovdata.new(governor: allow)
    result = tool.call(reference: "LOV-2021-06-18-97", action: "search", section: "4-1")

    assert result.ok?, result.to_s
    assert_includes result.value!, "https://lovdata.no/dokument/NL/lov/2021-06-18-97/%C2%A74-1"
    refute_includes result.value!, "barnevernsloven"
  end

  def test_lovdata_accepts_only_official_single_document_urls
    tool = Master::Io::Lovdata.new(governor: allow)
    accepted = tool.call(reference: "https://lovdata.no/dokument/NL/lov/2021-06-18-97", action: "search")
    rejected = tool.call(reference: "https://lovdata.no.evil.example/dokument/NL/lov/2021-06-18-97", action: "search")

    assert accepted.ok?
    assert_includes accepted.value!, "lovdata.no/dokument/NL/lov"
    refute rejected.ok?
  end

  def test_lovdata_rejects_arbitrary_urls_without_searching
    tool = Master::Io::Lovdata.new(governor: allow)
    fake = Object.new
    fake.define_singleton_method(:call) { |**_args| raise "search must not run for a URL input" }
    tool.instance_variable_set(:@search, fake)

    result = tool.call(reference: "https://lovdata.no.evil.example/dokument/NL/lov/2021-06-18-97", action: "search")

    refute result.ok?
    assert_equal :validation, result.category
  end

  def test_lovdata_search_filters_unofficial_search_results
    tool = Master::Io::Lovdata.new(governor: allow)
    search = Master::Result.ok(<<~TEXT)
      1. Official law
      https://lovdata.no/dokument/NL/lov/2021-06-18-97
      Official result

      2. Lookalike
      https://lovdata.no.evil.example/dokument/NL/lov/2021-06-18-97
      Fake result
    TEXT
    with_stubbed_search(tool, search) do
      result = tool.call(reference: "barnevernsloven", action: "search")
      assert result.ok?, result.to_s
      assert_includes result.value!, "Official law"
      refute_includes result.value!, "evil.example"
    end
  end

  def test_lovdata_text_lookup_requires_operator_ai_use_acknowledgement
    tool = Master::Io::Lovdata.new(governor: allow)
    with_env("MASTER_LOVDATA_AI_USE", nil) do
      result = tool.call(reference: "LOV-2021-06-18-97", action: "lookup")
      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/no storage or model training/, result.message)
    end
  end

  def test_lovdata_lookup_fetches_one_document_only_after_acknowledgement
    tool = Master::Io::Lovdata.new(governor: allow)
    fetcher = Object.new
    fetcher.define_singleton_method(:call) do |url:, full:|
      raise "unexpected bulk/full fetch" if full
      raise "unexpected URL" unless url == "https://lovdata.no/dokument/NL/lov/2021-06-18-97/%C2%A74-1"
      Master::Result.ok("§ 4-1. Barnets beste\\nBarnets beste skal være et grunnleggende hensyn.")
    end
    tool.instance_variable_set(:@fetch, fetcher)
    with_env("MASTER_LOVDATA_AI_USE", Master::Io::Lovdata::AI_USE_ACK) do
      result = tool.call(reference: "LOV-2021-06-18-97", section: "4-1")
      assert result.ok?, result.to_s
      assert_includes result.value!, "Barnets beste"
      assert_includes result.value!, "Source: https://lovdata.no/"
    end
  end

  def test_linguist_returns_only_allowlisted_dictionary_and_authority_sources
    tool = Master::Io::Linguist.new(governor: allow)
    search = Master::Result.ok(<<~TEXT)
      1. Bokmålsordboka
      https://ordbokene.no/bm/123
      Meaning and inflection

      2. Untrusted lookalike
      https://ordbokene.no.attacker.invalid/bm/123
      Fake result
    TEXT
    with_stubbed_search(tool, search) do
      result = tool.call(term: "arbeidsom", language: "nb", focus: "meaning")
      assert result.ok?, result.to_s
      assert_includes result.value!, "ordbokene.no/bm/123"
      refute_includes result.value!, "attacker.invalid"
    end
  end

  def test_linguist_bounds_focus_language_and_results
    tool = Master::Io::Linguist.new(governor: allow)
    queries = []
    fake = Object.new
    fake.define_singleton_method(:call) do |query:|
      queries << query
      Master::Result.ok("1. Cambridge\nhttps://dictionary.cambridge.org/dictionary/english/nuance\nA subtle difference in meaning.")
    end
    tool.instance_variable_set(:@search, fake)

    result = tool.call(term: "nuance", language: "en", focus: "etymology", limit: 99)

    assert result.ok?, result.to_s
    assert_equal 1, result.value!.scan(/Cambridge/).length
    assert_includes queries.first, "etymology"
    assert_includes queries.first, "site:dictionary.cambridge.org"
  end

  def test_research_router_selects_lovdata_and_linguist_for_explicit_requests
    agent = Master::Review::Agent.allocate
    agent.define_singleton_method(:evidence_tool) { |name| name }

    assert_equal "Lovdata", agent.send(:specialized_web_source, "What does Lovdata say about arbeidsmiljøloven § 15-7?")
    assert_equal "Linguist", agent.send(:specialized_web_source, 'Explain the pragmatics of "you are a character"')
    assert_nil agent.send(:specialized_web_source, "Explain the pragmatics and register of this phrase")
    assert_equal "Lovdata", agent.send(:specialized_web_source, "Look up LOV-2021-06-18-97")
    law = agent.send(:specialized_web_args, "Look up LOV-2021-06-18-97 § 4-1")
    assert_equal "LOV-2021-06-18-97", law.fetch(:reference)
    assert_equal "4-1", law.fetch(:section)
    linguistic = agent.send(:specialized_web_args, 'Study the etymology of "sonderweg" in English')
    assert_equal "sonderweg", linguistic.fetch(:term)
    assert_equal "en", linguistic.fetch(:language)
    assert_equal "etymology", linguistic.fetch(:focus)
  end

  def test_codepen_trending_extracts_public_pen_links_without_executing_them
    tool = Master::Io::CodePen.new(governor: allow)
    html = <<~HTML
      <a href="/alpha/pen/abc123"><span>Particle face</span></a>
      <a href="/beta/pen/def456">Editorial menu</a>
      <script>alert("ignore")</script>
    HTML
    tool.define_singleton_method(:get) { |_url| html }

    result = tool.call(mode: "trending", limit: 2)

    assert result.ok?, result.to_s
    assert_equal [
      { "title" => "Particle face", "user" => "alpha", "url" => "https://codepen.io/alpha/pen/abc123" },
      { "title" => "Editorial menu", "user" => "beta", "url" => "https://codepen.io/beta/pen/def456" },
    ], result.value!
  end

  def test_codepen_rejects_non_codepen_urls
    result = Master::Io::CodePen.new(governor: allow).call(
      mode: "inspect", url: "https://example.com/pen/nope",
    )

    refute result.ok?
    assert_equal :validation, result.category
  end

  def test_codepen_inspect_reads_each_public_panel_as_source_text
    tool = Master::Io::CodePen.new(governor: allow)
    requests = []
    panels = {
      "html" => "<h1 class='title'>Hello</h1>",
      "css" => ".title { font: 700 4rem/1.0 sans-serif; color: rebeccapurple; }",
      "js" => "/* JavaScript source panel fixture */",
    }
    tool.define_singleton_method(:get) do |url|
      requests << url
      panels.fetch(url.split(".").last)
    end

    result = tool.call(mode: "inspect", url: "https://codepen.io/uisato/pen/example")

    assert result.ok?, result.to_s
    assert_equal [
      "https://codepen.io/uisato/pen/example.html",
      "https://codepen.io/uisato/pen/example.css",
      "https://codepen.io/uisato/pen/example.js",
    ], requests
    assert_equal %w[html css js], result.value!.map { |panel| panel.fetch("type") }
    css = result.value!.find { |panel| panel["type"] == "css" }.fetch("source")
    assert_includes css, "font: 700 4rem/1.0"
    assert_includes css, "rebeccapurple"
  end

  def test_gist_requires_a_public_gist_url_and_returns_source_text
    tool = Master::Io::Gist.new(governor: allow)
    body = JSON.generate({
      "files" => {
        "hello.rb" => { "content" => "puts :hello\n" },
        "note.md" => { "content" => "# note\n" },
      },
    })
    response = Struct.new(:code, :body).new("200", body)
    tool.define_singleton_method(:http) { |_uri, _address| response }

    result = tool.call(url: "https://gist.github.com/alice/0123456789abcdef")

    assert result.ok?, result.to_s
    assert_includes result.value!, "## hello.rb"
    assert_includes result.value!, "puts :hello\n"
    assert_includes result.value!, "## note.md"
  end

  def test_gist_rejects_non_gist_urls
    result = Master::Io::Gist.new(governor: allow).call(
      url: "https://github.com/alice/repo",
    )

    refute result.ok?
    assert_equal :validation, result.category
  end

  def test_youtube_transcript_accepts_video_id_and_never_needs_audio_execution
    tool = Master::Io::YoutubeTranscript.new(governor: allow)
    tool.define_singleton_method(:caption_track) { |_video_id, language:| { "baseUrl" => "https://example.test/captions" } }
    tool.define_singleton_method(:download) { |_url, timestamps:| timestamps ? "[00:00:01] hello" : "hello" }

    result = tool.call(url: "dQw4w9WgXcQ", timestamps: true)

    assert result.ok?, result.to_s
    assert_equal "[00:00:01] hello", result.value!
  end

  def test_youtube_transcript_rejects_lookalike_hosts_and_reports_caption_http_errors
    tool = Master::Io::YoutubeTranscript.new(governor: allow)
    refute tool.call(url: "https://evil.example/youtu.be/dQw4w9WgXcQ").ok?

    tool.define_singleton_method(:caption_track) { |_video_id, language:| { "baseUrl" => "https://example.test/captions" } }
    tool.define_singleton_method(:get_response) { |_url| Struct.new(:code, :body).new("503", "unavailable") }
    result = tool.call(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    refute result.ok?
    assert_equal :infrastructure, result.category
    assert_match(/caption HTTP 503/, result.message)
  end

  def test_youtube_transcript_rejects_an_unrelated_url
    result = Master::Io::YoutubeTranscript.new(governor: allow).call(
      url: "https://example.com/watch?v=dQw4w9WgXcQ",
    )

    refute result.ok?
    assert_equal :validation, result.category
  end

  def test_host_files_inspects_home_and_absolute_paths_read_only
    root = Dir.mktmpdir("host_files_")
    home = File.join(root, "home")
    FileUtils.mkdir_p(File.join(home, "Documents"))
    File.write(File.join(home, "Documents", "notes.txt"), "readable host data\n")
    tool = Master::Io::HostFiles.new(governor: allow, home:)
    relative = tool.call(action: "read", path: "Documents/notes.txt")
    absolute = tool.call(action: "info", path: File.join(home, "Documents", "notes.txt"))
    assert relative.ok?, relative.to_s
    assert_includes relative.value!, "readable host data"
    assert absolute.ok?, absolute.to_s
    assert_includes absolute.value!, "readable: true"
    assert_equal "readable host data\n", File.read(File.join(home, "Documents", "notes.txt"))
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_host_files_refuses_private_keys_but_can_read_ssh_config
    root = Dir.mktmpdir("host_files_keys_")
    FileUtils.mkdir_p(File.join(root, ".ssh"))
    File.write(File.join(root, ".ssh", "id_ed25519"), "key")
    File.write(File.join(root, ".ssh", "config"), "Host example\n")
    tool = Master::Io::HostFiles.new(governor: allow, home: root)
    key = tool.call(action: "read", path: ".ssh/id_ed25519")
    config = tool.call(action: "read", path: ".ssh/config")
    refute key.ok?
    assert_equal :policy, key.category
    assert config.ok?, config.to_s
    assert_includes config.value!, "Host example"
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_github_repo_miner_returns_bounded_ranked_metadata_without_running_code
    tool = Master::Io::GitHubRepoMiner.new(governor: allow)
    body = JSON.generate({
      "total_count" => 1,
      "items" => [{
        "full_name" => "ruby/example",
        "html_url" => "https://github.com/ruby/example",
        "description" => "A Ruby example project",
        "stargazers_count" => 123,
        "forks_count" => 12,
        "language" => "Ruby",
        "updated_at" => "2026-10-20T10:00:00Z",
      }],
    })
    tool.define_singleton_method(:fetch_response) do |query:, sort:, limit:|
      raise "unexpected normalized query: #{query}" unless query == "Ruby"
      raise "unexpected sort: #{sort}" unless sort == "stars"
      raise "unexpected limit: #{limit}" unless limit == 1
      Struct.new(:code, :body).new("200", body)
    end

    result = tool.call(query: "Find popular GitHub repos for Ruby", sort: "stars", limit: 1)

    assert result.ok?, result.to_s
    assert_includes result.value!, "ruby/example"
    assert_includes result.value!, "https://github.com/ruby/example"
    assert_includes result.value!, "123 stars"
  end

  def test_arxiv_research_returns_abstract_and_ar5iv_html_link
    tool = Master::Io::ArxivResearch.new(governor: allow)
    feed = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <id>http://arxiv.org/abs/2401.12345v1</id>
          <title>Rendering Future Faces</title>
          <summary>A study of robust rendering and perceptual geometry.</summary>
          <published>2024-01-20T00:00:00Z</published>
          <author><name>Alice Example</name></author>
        </entry>
      </feed>
    XML
    tool.define_singleton_method(:search_response) do |query:, sort_by:, limit:|
      raise "unexpected normalized query: #{query}" unless query == "rendering"
      raise "unexpected sort: #{sort_by}" unless sort_by == "relevance"
      raise "unexpected limit: #{limit}" unless limit == 5
      Struct.new(:code, :body).new("200", feed)
    end

    result = tool.call(query: "Review arXiv research papers on rendering")

    assert result.ok?, result.to_s
    assert_includes result.value!, "Rendering Future Faces"
    assert_includes result.value!, "https://arxiv.org/abs/2401.12345v1"
    assert_includes result.value!, "https://ar5iv.labs.arxiv.org/html/2401.12345v1"
    assert_includes result.value!, "robust rendering and perceptual geometry"
  end

  def test_research_source_routing_selects_matching_adapter_and_arguments
    agent = Master::Review::Agent.allocate
    agent.define_singleton_method(:evidence_tool) { |name| name }

    assert_equal "GitHubRepoMiner", agent.send(:specialized_web_source, "Find popular GitHub repos for Ruby")
    github = agent.send(:specialized_web_args, "Find recent GitHub repositories for Ruby")
    assert_equal "updated", github.fetch(:sort)
    assert_equal 5, github.fetch(:limit)

    assert_equal "ArxivResearch", agent.send(:specialized_web_source, "Review arXiv research papers on rendering")
    paper = agent.send(:specialized_web_args, "Review arXiv research papers on rendering")
    assert_equal "Review arXiv research papers on rendering", paper.fetch(:query)

    assert_equal "YoutubeTranscript", agent.send(:specialized_web_source, "Get YouTube transcript for dQw4w9WgXcQ with timestamps")
    transcript = agent.send(:specialized_web_args, "Get YouTube transcript for dQw4w9WgXcQ with timestamps")
    assert_equal "dQw4w9WgXcQ", transcript.fetch(:url)
    assert transcript.fetch(:timestamps)
  end

  def test_tree_has_safe_tool_identity_and_a_live_llm_adapter
    assert_equal "tree", Master::Io::Tree::NAME
    assert_equal :safe, Master::Io::Tree::TIER
    assert_equal Master::Io::LLM::Tree, Master::Review::LLMDispatcher::LLM_TOOL_MAP.fetch(Master::Io::Tree)
  end

  def test_research_sources_are_registered_once
    names = Master::Builder::DEFAULT_TOOL_MAP.keys
    assert_equal 1, names.count("Tree")
    assert_equal 1, names.count("CodePen")
    assert_equal 1, names.count("Gist")
    assert_equal 1, names.count("YouTubeTranscript")
    assert_equal 1, names.count("HostFiles")
    assert_equal 1, names.count("GitHubRepoMiner")
    assert_equal 1, names.count("ArxivResearch")
  end

  def test_llm_dispatch_has_the_research_sources
    map = Master::Review::LLMDispatcher::LLM_TOOL_MAP
    assert_equal Master::Io::LLM::Tree, map.fetch(Master::Io::Tree)
    assert_equal Master::Io::LLM::CodePen, map.fetch(Master::Io::CodePen)
    assert_equal Master::Io::LLM::Gist, map.fetch(Master::Io::Gist)
    assert_equal Master::Io::LLM::YoutubeTranscript, map.fetch(Master::Io::YoutubeTranscript)
    assert_equal Master::Io::LLM::HostFiles, map.fetch(Master::Io::HostFiles)
    assert_equal Master::Io::LLM::GitHubRepoMiner, map.fetch(Master::Io::GitHubRepoMiner)
    assert_equal Master::Io::LLM::ArxivResearch, map.fetch(Master::Io::ArxivResearch)
  end
end
