# frozen_string_literal: true

require_relative "test_helper"

# Two provider bridges that must fail soft. McpCoordinator connects only the
# servers data/mcp_servers.yml enables, and a server that will not start is an
# event rather than a boot failure. WebChat drives a browser page by selectors
# from data/models.yml, and is off unless something turns it on.
class TestIoMcpAndWebChat < Minitest::Test
  Bus = Struct.new(:events) do
    def publish(name, **payload) = events << [name, payload]
  end

  FakeClient = Struct.new(:started, :fail) do
    def start
      raise "npx missing" if fail

      self.started = true
    end
  end

  def coordinator_with(servers_yaml)
    root = Dir.mktmpdir("mcp_")
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "mcp_servers.yml"), servers_yaml)
    [Master::Io::McpCoordinator.new(root:, event_bus: Bus.new([])), root]
  end

  def test_only_enabled_servers_with_a_known_transport_connect
    coordinator, root = coordinator_with(<<~YAML)
      servers:
        off: { enabled: false, command: npx }
        local: { command: npx, args: [-y, server] }
        remote: { transport: sse, url: "http://127.0.0.1:1" }
        odd: { transport: carrier_pigeon }
        broken: { command: nope }
    YAML
    built = []
    build = lambda do |name, transport, config|
      built << [name, transport, config]
      FakeClient.new(false, name == "broken")
    end
    coordinator.stub(:build_mcp_client, build) { coordinator.connect_all }
    events = coordinator.instance_variable_get(:@bus).events

    assert_equal [["local", :stdio, { command: "npx", args: ["-y", "server"] }],
                  ["remote", :sse, { url: "http://127.0.0.1:1" }], ["broken", :stdio, { command: "nope", args: [] }]], built
    assert_includes events, ["mcp:server_failed", { name: "broken", error: "npx missing" }]
    assert_includes events, ["mcp:connected", { count: 2 }]
  ensure
    FileUtils.rm_rf(root)
  end

  def test_a_missing_config_connects_nothing_and_says_so
    coordinator = Master::Io::McpCoordinator.new(root: Dir.mktmpdir("mcp_empty_"), event_bus: Bus.new([]))
    coordinator.connect_all

    assert_equal [["mcp:connected", { count: 0 }]], coordinator.instance_variable_get(:@bus).events
    assert_empty coordinator.tools
  end

  def test_web_chat_is_off_without_an_opt_in
    chat = Master::Io::WebChat.new(provider: "grok")
    with_env("MASTER_WEB_CHAT" => nil, "MASTER_KEYLESS" => nil) do
      Master.stub(:keyless_llm_enabled?, false) do
        assert_raises(Master::Io::WebChat::DisabledError) { chat.ask(prompt: "hi") }
      end
    end
  end

  def test_an_unknown_provider_is_refused_at_construction
    assert_raises(Master::Io::WebChat::ProviderError) { Master::Io::WebChat.new(provider: "altavista") }
  end

  Node = Struct.new(:text, :inner_html)

  class Page
    def initialize(nodes) = @nodes = nodes
    def at_css(css) = @nodes[css]
  end

  def test_selectors_are_tried_in_order_and_markup_is_a_fallback_for_text
    chat = Master::Io::WebChat.new(provider: "grok")
    page = Page.new(".second" => Node.new("", "<p>hello <b>there</b></p>"))

    node = chat.send(:find_element, page, ".first, .second")
    assert_equal "hello there", chat.send(:extract_text, node)
    assert_nil chat.send(:find_element, page, ".none")
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
