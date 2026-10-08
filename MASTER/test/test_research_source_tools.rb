# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestResearchSourceTools < Minitest::Test
  Governor = Struct.new(:answer, :asked) do
    def permit?(name, tier, detail)
      (self.asked ||= []) << [name, tier, detail]
      answer
    end
  end

  def allow = Governor.new(Master::Result.ok(true))

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

  def test_youtube_transcript_rejects_an_unrelated_url
    result = Master::Io::YoutubeTranscript.new(governor: allow).call(
      url: "https://example.com/watch?v=dQw4w9WgXcQ",
    )

    refute result.ok?
    assert_equal :validation, result.category
  end

  def test_research_sources_are_registered_once
    names = Master::Builder::DEFAULT_TOOL_MAP.keys
    assert_equal 1, names.count("CodePen")
    assert_equal 1, names.count("Gist")
    assert_equal 1, names.count("YouTubeTranscript")
  end

  def test_llm_dispatch_has_the_research_sources
    map = Master::Review::LLMDispatcher::LLM_TOOL_MAP
    assert_equal Master::Io::LLM::CodePen, map.fetch(Master::Io::CodePen)
    assert_equal Master::Io::LLM::Gist, map.fetch(Master::Io::Gist)
    assert_equal Master::Io::LLM::YoutubeTranscript, map.fetch(Master::Io::YoutubeTranscript)
  end
end
