# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

# MASTER answered "I can't browse Temu from here" because web_fetch returns a script
# shell for a JavaScript shop and no tool rendered the page. web_browse is that tool;
# these pin that it is registered where the model is handed tools, that it refuses
# what web_fetch refuses, and that a request naming a site reaches it.
class TestWebBrowse < Minitest::Test
  Router = Master::Ground::EvidenceRouter

  class Governor
    def permit?(*) = Master::Result.ok(true)
  end

  def tool = Master::Io::WebBrowse.new(governor: Governor.new)

  def test_it_refuses_internal_and_non_http_addresses_before_starting_a_browser
    %w[http://127.0.0.1/ http://169.254.169.254/latest/meta-data/ http://localhost:3000/].each do |url|
      assert tool.call(url:).err?, "#{url} must be refused"
    end
    assert tool.call(url: "file:///etc/passwd").err?
  end

  def test_it_is_registered_for_the_builder_the_llm_and_the_catalogue
    assert Master::Builder::DEFAULT_TOOL_MAP.key?("WebBrowse")
    assert_equal Master::Io::LLM::WebBrowse, Master::Review::LLMDispatcher::LLM_TOOL_MAP.fetch(Master::Io::WebBrowse)
    names = YAML.safe_load_file(File.join(Master::ROOT, "data", "tools.yml")).map { |row| row["name"] }
    assert_includes names, "WebBrowse"
  end

  def test_a_request_naming_a_site_routes_to_the_browser
    assert_equal :browser, Router.classify("hi, can you find me a decent movie wall projector at temu.com?")
    assert_equal :browser, Router.classify("check https://www.kjell.com/no/sok?query=projektor for cheap ones")
  end

  def test_file_names_are_still_repository_questions
    assert_equal :repository, Router.classify("what is in lib/fix/fix_loop.rb")
    assert_equal :repository, Router.classify("open notes.md and summarise it")
  end

  def test_the_browser_prompt_names_the_tool_and_forbids_giving_up_untried
    prompt = Router.prompt_for(:browser)
    assert_includes prompt, "WebBrowse"
    assert_includes prompt, "Try WebBrowse before saying a site cannot be read"
  end
end
