# frozen_string_literal: true

require_relative "test_helper"
# McpToolWrapper is not an autoloaded name: it lives in mcp_coordinator.rb, so a
# test that reaches it before anything touches McpCoordinator needs the file.
require_relative "../lib/io/mcp_coordinator"

# Two provider bridges that must fail soft. McpCoordinator connects only the
# servers data/mcp_servers.yml enables, and a server that will not start is an
# event rather than a boot failure. WebChat drives a browser page by selectors
# from data/models.yml, and is off unless something turns it on.
class TestIoMcpAndWebChat < Minitest::Test
  Bus = Struct.new(:events) do
    def publish(name, **payload) = events << [name, payload]
  end

  class FakeClient
    def initialize(fail:)
      @fail = fail
    end

    def connect
      raise "npx missing" if @fail

      @connected = true
    end

    def tools = []
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
      FakeClient.new(fail: name == "broken")
    end
    coordinator.stub(:build_mcp_client, build) { coordinator.connect_all }
    events = coordinator.instance_variable_get(:@bus).events

    assert_equal [
      ["local", :stdio, { "command" => "npx", "args" => ["-y", "server"] }],
      ["remote", :sse, { "transport" => "sse", "url" => "http://127.0.0.1:1" }],
      ["broken", :stdio, { "command" => "nope" }],
    ], built
    assert_includes events, ["mcp:server_failed", { name: "broken", error_digest: Digest::SHA256.hexdigest("npx missing"), error_bytes: "npx missing".bytesize }]
    refute_includes events.inspect, "npx missing"
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

  FakeMcpTool = Struct.new(:name, :description)

  class Permit
    attr_reader :message

    def initialize(ok:, message: "")
      @ok = ok
      @message = message
    end

    def ok? = @ok
  end

  class Governor
    attr_reader :calls

    def initialize(permit = true)
      @permit = permit
      @calls = []
    end

    def permit?(tool, tier, description)
      @calls << [tool, tier, description]
      Permit.new(ok: @permit, message: "denied")
    end
  end

  def test_mcp_tool_runs_through_the_governor
    client = Struct.new(:calls) do
      def call_tool(tool:, arguments:)
        calls << [tool.name, arguments]
        { "result" => { "content" => [{ "type" => "text", "text" => "ok" }] } }
      end
    end.new([])
    governor = Governor.new
    tool = Master::Io::McpToolWrapper.new(
      name: "filesystem",
      client:,
      tool: FakeMcpTool.new("read_file", "read a file"),
      governor:,
      event_bus: Bus.new([]),
      timeout: 2,
      tier: :dangerous,
    )

    assert_equal JSON.generate([{ "type" => "text", "text" => "ok" }]), tool.execute(path: "README.md")
    assert_equal [["filesystem__read_file", :dangerous, tool.description]], governor.calls
    assert_equal [["read_file", { path: "README.md" }]], client.calls
  end

  def test_mcp_tool_error_event_redacts_server_error_text
    client = Struct.new(:calls) do
      def call_tool(tool:, arguments:)
        calls << [tool.name, arguments]
        raise "token=private-secret at /home/private/user.txt"
      end
    end.new([])
    bus = Bus.new([])
    tool = Master::Io::McpToolWrapper.new(
      name: "filesystem", client:,
      tool: FakeMcpTool.new("read_file", "read a file"),
      governor: Governor.new, event_bus: bus, timeout: 2
    )

    result = tool.execute(path: "private.txt")
    event = bus.events.find { |name, _payload| name == "mcp:tool_after" }

    assert_includes result, "token=private-secret"
    refute_nil event
    payload = event.last
    assert_equal Digest::SHA256.hexdigest("token=private-secret at /home/private/user.txt"), payload[:error_digest]
    assert_equal "token=private-secret at /home/private/user.txt".bytesize, payload[:error_bytes]
    refute payload.key?(:error)
    refute_includes bus.events.inspect, "private-secret"
    refute_includes bus.events.inspect, "/home/private/user.txt"
  end

  def test_mcp_tool_refuses_before_calling_the_server
    client = Struct.new(:calls) do
      def call_tool(*args)
        calls << args
        raise "must not run"
      end
    end.new([])
    governor = Governor.new(false)
    tool = Master::Io::McpToolWrapper.new(
      name: "filesystem",
      client:,
      tool: FakeMcpTool.new("write_file", "write a file"),
      governor:,
      event_bus: Bus.new([]),
      timeout: 2,
    )

    assert_equal "MCP tool refused: denied", tool.execute(path: "README.md")
    assert_empty client.calls
  end

  # Web chat is on by default; either switch turns it off before a browser starts.
  def test_web_chat_switched_off_refuses_before_opening_a_browser
    chat = Master::Io::WebChat.new(provider: "grok")
    [{ "MASTER_WEB_CHAT" => "0" }, { "MASTER_NO_WEB_CHAT" => "1" }].each do |switch|
      with_env(switch) do
        assert_raises(Master::Io::WebChat::DisabledError) { chat.ask(prompt: "hi") }
      end
    end
  end

  def test_an_unknown_provider_is_refused_at_construction
    assert_raises(Master::Io::WebChat::ProviderError) { Master::Io::WebChat.new(provider: "altavista") }
  end

  Node = Struct.new(:text, :html) do
    def property(_name) = html
  end

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
