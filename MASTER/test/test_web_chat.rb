# frozen_string_literal: true

require_relative "test_helper"

class TestWebChat < Minitest::Test
  class FakeNode
    attr_reader :text

    def initialize(page, text = "", attributes = {})
      @page = page
      @text = text
      @attributes = attributes
    end

    def attribute(name) = @attributes[name]

    def focus = self

    def type(text, *)
      @page.submit(text)
      self
    end

    def inner_html = text
  end

  class FakePage
    attr_reader :url, :prompt, :screenshots

    PNG = ("\x89PNG\r\n\x1a\n".b + ("test-pixels" * 8).b).freeze

    def initialize(answer: "Fresh answer.", repeated: false)
      @answer = answer
      @repeated = repeated
      @submitted = false
      @reply_reads = 0
      @screenshots = []
      @input = FakeNode.new(self)
    end

    def go_to(url)
      @url = url
    end

    def at_css(selector)
      selector.include?("textarea") || selector.include?("contenteditable") ? @input : nil
    end

    def css(_selector)
      @reply_reads += 1
      old = FakeNode.new(self, "Earlier answer.", "data-message-author-role" => "assistant")
      return [old] unless @submitted

      user = FakeNode.new(self, @prompt, "class" => "message user")
      return [old, user] if @reply_reads < 3

      answer = @repeated ? "Earlier answer." : @answer
      [old, user, FakeNode.new(self, answer, "data-message-author-role" => "assistant")]
    end

    def submit(text)
      @submitted = true
      @prompt = text
    end

    def network = self

    def wait_for_idle(timeout:)
      true
    end

    def screenshot(encoding:, format:)
      @screenshots << { submitted: @submitted, format: }
      PNG
    end
  end

  def build_chat
    chat = Master::Io::WebChat.allocate
    chat.instance_variable_set(:@provider, "chatgpt")
    chat.instance_variable_set(:@config, {
      "url" => "https://chatgpt.com/",
      "input_selector" => "textarea",
      "reply_selector" => "div[data-message-author-role='assistant']",
      "timeout" => 3,
    })
    chat.define_singleton_method(:timeout_seconds) { 3 }
    chat.define_singleton_method(:sleep) { |seconds| Thread.pass }
    chat
  end

  def test_browser_chat_returns_the_new_answer_and_captures_each_visible_stage
    chat = build_chat
    page = FakePage.new

    result = chat.send(:converse, page, "What is new?")

    assert_equal "Fresh answer.", result
    assert_equal "What is new?", page.prompt
    assert_equal [
      { stage: "loaded", submitted: false },
      { stage: "submitted", submitted: true },
      { stage: "answered", submitted: true },
    ], chat.screenshot_evidence.map { |row| { stage: row.fetch(:stage), submitted: page.screenshots.shift.fetch(:submitted) } }
  end

  def test_identical_repeated_answer_is_valid_when_a_new_assistant_turn_appears
    chat = build_chat
    page = FakePage.new(repeated: true)

    assert_equal "Earlier answer.", chat.send(:converse, page, "Ask the same thing again")
    assert_equal %w[loaded submitted answered], chat.screenshot_evidence.map { |row| row.fetch(:stage) }
  end

  def test_screenshots_are_not_saved_without_an_explicit_directory
    old = ENV.delete("MASTER_WEB_CHAT_SCREENSHOT_DIR")
    chat = build_chat
    chat.instance_variable_set(:@screenshot_evidence, [])
    page = FakePage.new

    chat.send(:capture_screenshot, page, stage: "loaded")

    evidence = chat.screenshot_evidence.fetch(0)
    assert_equal "loaded", evidence.fetch(:stage)
    assert_operator evidence.fetch(:bytes), :>, 64
    assert_match(/\A[0-9a-f]{64}\z/, evidence.fetch(:sha256))
    refute evidence.key?(:path)
  ensure
    old.nil? ? ENV.delete("MASTER_WEB_CHAT_SCREENSHOT_DIR") : ENV["MASTER_WEB_CHAT_SCREENSHOT_DIR"] = old
  end
end
