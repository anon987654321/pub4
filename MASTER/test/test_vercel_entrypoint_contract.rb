# frozen_string_literal: true

require "json"
require "minitest/autorun"

class TestVercelEntrypointContract < Minitest::Test
  ROOT = File.expand_path("../..", __dir__).freeze

  def test_vercel_serves_an_explicit_static_output_directory
    config = JSON.parse(File.read(File.join(ROOT, "vercel.json"), encoding: "UTF-8"))

    assert_nil config.fetch("framework")
    assert_equal "public", config.fetch("outputDirectory")
    assert File.file?(File.join(ROOT, config.fetch("outputDirectory"), "index.html")),
           "configured Vercel output directory must contain its index"
  end

  def test_static_index_is_truthful_and_links_every_governed_tree
    html = File.read(File.join(ROOT, "public", "index.html"), encoding: "UTF-8")

    assert_match(/\A<!doctype html>/i, html)
    assert_includes html, "does not boot MASTER"
    assert_includes html, "does not prove that the runtime or production host is healthy"
    refute_match(/<script\b/i, html, "repository index should stay static")

    %w[MASTER RAILS OPENBSD STUDIO].each do |tree|
      assert_includes html, "https://github.com/anon987654321/pub4/tree/main/#{tree}"
    end
  end
end
