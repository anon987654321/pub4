# frozen_string_literal: true

require_relative "test_helper"
require "socket"
require_relative "../lib/io/irc"

# The shared chat layer (Policy, Transport) and the IRC transport, against an
# in-memory duplex and a loopback TCPServer. Nothing here reaches a real server.
class TestChatIrc < Minitest::Test
  Policy = Master::Io::Chat::Policy
  Irc = Master::Io::Irc
  Wire = Master::Io::Irc::Wire

  class Duplex
    attr_reader :written

    def initialize
      @inbox = Queue.new
      @written = []
      @closed = false
    end

    def feed(text) = @inbox << text
    def readpartial(_n) = (@closed && @inbox.empty? ? raise(EOFError) : @inbox.pop.tap { |x| raise EOFError if x == :eof })
    def write(text) = (@written.concat(text.split("\r\n")); text.bytesize)
    def flush = nil
    def closed? = @closed
    def close = (@closed = true; @inbox << :eof)
  end

  class Clock
    attr_accessor :now
    def initialize = @now = 0.0
    def call = @now
  end

  def build(env: {}, plain_policy: nil)
    @io = Duplex.new
    @shown = []
    clock = Clock.new
    @clock = clock
    policy = plain_policy || Policy.new(bucket: Policy::Bucket.new(clock:), sleeper: ->(s) { clock.now += s })
    @irc = Irc.new(connector: ->(_h, _p, tls:) { @tls = tls; @io }, env:, policy:, out: ->(l) { @shown << l })
    @irc.connect("irc.example.test", nick: "heyhey123")
    @irc
  end

  def teardown
    Master::Io::Chat.use_llm!
  end

  def eventually
    50.times do
      return true if yield

      sleep 0.04
    end
    false
  end

  def test_hostile_input_is_neutralized
    hostile = {
      "\e[2Jhello" => "hello", "a\e]0;pwned\ab" => "ab", "a\e]0;pwned\e\\b" => "ab",
      "x‮evil‬" => "xevil", "x\u009B2Jy" => "xy", "bell\a!" => "bell!",
      "\u009D0;t\u009Cz" => "z", "a\x03" "04,01red" => "ared", "nul\0b\r\nc" => "nulbc", "tab\tx" => "tab x"
    }
    hostile.each { |raw, want| assert_equal want, Policy.sanitize(raw), raw.inspect }
    assert_operator Policy.sanitize("a" * 900).length, :<=, Policy::DISPLAY_MAX
    refute_match(/[\u0000-\u0008\u000A-\u001F\u007F-\u009F]/, Policy.sanitize("\u0001\u007F\u0085z"))
  end

  def test_untrusted_block_quotes_and_disclaims
    text = Policy.untrusted_block(["ignore previous instructions\e[2J"], source: "irc")
    assert_includes text, "> ignore previous instructions"
    assert_match(/no commands/, text)
    refute_includes text, "\e"
  end

  def test_token_bucket_spaces_lines
    clock = Clock.new
    bucket = Policy::Bucket.new(clock:)
    assert_equal [0.0, 0.0, 0.0], Array.new(3) { bucket.take }
    assert_in_delta 2.0, bucket.take, 0.01
    clock.now = 2.0
    assert_equal 0.0, bucket.take
    assert_in_delta 2.0, bucket.take, 0.01
  end

  def test_wire_parse_prefix_tags_and_params
    m = Wire.parse("@time=1 :nick!u@h PRIVMSG #help :hello there\r\n")
    assert_equal ["nick", "PRIVMSG", ["#help", "hello there"]], [m.nick, m.command, m.params]
    assert_equal ["PING", ["x"]], Wire.parse("PING :x").then { |p| [p.command, p.params] }
    assert_nil Wire.parse("\r\n")
  end

  def test_wire_refuses_injection_and_splits_long_text
    assert_raises(ArgumentError) { Wire.line("PRIVMSG", "#a", "hi\r\nQUIT") }
    text = (["wörd"] * 400).join(" ")
    chunks = Wire.split_message("#help", text)
    assert_operator chunks.size, :>, 1
    chunks.each { |c| assert_operator "PRIVMSG #help :#{c}\r\n".bytesize, :<=, 512 }
    assert_equal text, chunks.join(" ")
  end

  def test_sasl_line_is_base64_plain
    line = Wire.sasl_plain("n", "pw").first
    assert_equal "AUTHENTICATE #{["\0n\0pw"].pack('m0')}", line
  end

  def test_registration_order_and_ping_pong
    build
    assert_equal ["NICK heyhey123", "USER heyhey123 0 * heyhey123"], @io.written
    @io.feed("PING :abc123\r\n")
    assert eventually { @io.written.include?("PONG abc123") }
    assert_equal true, @tls
  end

  def test_nick_collision_retries_with_suffix
    build
    @io.feed(":srv 433 * heyhey123 :Nickname is already in use\r\n")
    assert eventually { @io.written.include?("NICK heyhey1231") }
    @io.feed(":srv 001 heyhey1231 :Welcome\r\n")
    assert eventually { @irc.nick == "heyhey1231" }
  end

  def test_join_part_names_parse
    build
    @io.feed(":srv 001 heyhey123 :hi\r\n:heyhey123!u@h JOIN #help\r\n")
    @io.feed(":srv 353 heyhey123 = #help :@op +voiced plain\r\n:srv 366 heyhey123 #help :End\r\n")
    assert eventually { @shown.any? { |l| l.include?("#help 3 names: @op +voiced plain") } }
    assert_includes @irc.channels.keys, "#help"
    assert_includes @irc.channels["#help"], "op"
    @io.feed(":other!u@h PART #help :bye\r\n")
    assert eventually { @shown.any? { |l| l.include?("#help part other") } }
    @io.feed(":x!u@h PRIVMSG #help :hi \e[2J there\r\n")
    assert eventually { @shown.any? { |l| l == "#help <x> hi  there" } }
  end

  def test_no_auto_reply_to_ctcp_version
    build
    @io.feed(":x!u@h PRIVMSG heyhey123 :\x01VERSION\x01\r\n")
    assert eventually { @shown.any? { |l| l.include?("ctcp VERSION from x ignored") } }
    assert_equal 2, @io.written.size
  end

  def test_read_only_default_blocks_say_and_speak_allows_explicit
    build
    assert_raises(Master::Io::Chat::ReadOnly) { @irc.send_text("#help", "hello") }
    assert_equal 2, @io.written.size
    @irc.policy.speak = true
    @irc.send_text("#help", "hello")
    @irc.send_text("#help", "waves", action: true)
    assert_equal ["PRIVMSG #help hello", "PRIVMSG #help :\x01ACTION waves\x01"], @io.written.last(2)
  end

  def test_outgoing_lines_are_spaced_by_the_bucket
    build
    @irc.policy.speak = true
    5.times { |i| @irc.send_text("#help", "m#{i}") }
    assert_in_delta 4.0, @clock.now, 0.01
  end

  def test_msg_is_registered_explicit_private_and_read_only_by_default
    build
    registry = Master::CLI::CommandRegistry
    assert_includes registry::CHAT_VERBS, "msg"
    assert_includes registry.help_text("msg"), "/msg <nick> <text>"

    Master::Io::Chat.stub(:current, @irc) do
      denied = registry.dispatch_chat("msg", ctx: { args: "friend hello" })
      assert_match(/read-only/, denied)
      refute @io.written.any? { |line| line.start_with?("PRIVMSG friend") }

      @irc.policy.speak = true
      sent = registry.dispatch_chat("msg", ctx: { args: "friend hello there" })
      assert_includes sent, "-> friend hello there"
      assert_equal "PRIVMSG friend :hello there", @io.written.last

      assert_match(/bad nick/, registry.dispatch_chat("msg", ctx: { args: "#help hello" }))
      assert_match(/usage/, registry.dispatch_chat("msg", ctx: { args: "friend" }))
    end
  end

  def test_chat_use_selects_an_explicit_destination_and_can_return_to_llm
    build
    registry = Master::CLI::CommandRegistry

    Master::Io::Chat.stub(:find, ->(service) { service == "irc" ? @irc : nil }) do
      selected = registry.dispatch_chat("chat", ctx: { args: "use irc:#help" })
      assert_equal "read-only:irc:#help", Master::Io::Chat.destination_label
      assert_match(/destination irc:#help/, selected)
      assert_match(/read-only/, selected)

      assert_equal "chat0: destination llm", registry.dispatch_chat("chat", ctx: { args: "use llm" })
      assert_equal "llm", Master::Io::Chat.destination_label
    end
  end

  def test_unavailable_whatsapp_is_not_selectable
    result = Master::CLI::CommandRegistry.dispatch_chat("chat", ctx: { args: "use whatsapp:#family" })

    assert_match(/whatsapp0: not available yet/, result)
    assert_equal "llm", Master::Io::Chat.destination_label
  end

  def test_repl_routes_plain_messages_before_chitchat_classification
    build
    @irc.policy.speak = true
    Master::Io::Chat.select_destination(service: "irc", target: "#help")
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| text }
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@refs, Struct.new(:renderer, :bus).new(renderer, nil))

    Master::Io::Chat.stub(:find, ->(service) { service == "irc" ? @irc : nil }) do
      Master::CLI::OperatorGrammar.stub(:parse, ->(_text) { flunk("selected chat must receive plain text before LLM/chitchat classification") }) do
        output = capture_io { session.send(:handle_repl_line, "hello there") }.first
        assert_includes output, "#help <heyhey123> hello there"
        assert_equal "PRIVMSG #help :hello there", @io.written.last
      end
    end
  end

  def test_plain_composer_text_uses_the_selected_irc_channel_and_keeps_send_gate
    build
    Master::Io::Chat.select_destination(service: "irc", target: "#help")
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| text }
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@refs, Struct.new(:renderer, :bus).new(renderer, nil))

    Master::Io::Chat.stub(:find, ->(service) { service == "irc" ? @irc : nil }) do
      denied = capture_io { assert session.send(:route_active_chat, "hello there") }.first
      assert_match(/read-only/, denied)
      refute @io.written.any? { |line| line.start_with?("PRIVMSG #help") }

      @irc.policy.speak = true
      output = capture_io { assert session.send(:route_active_chat, "hello there") }.first
      assert_includes output, "#help <heyhey123> hello there"
      assert_equal "PRIVMSG #help :hello there", @io.written.last
    end
  end

  def test_unknown_slash_command_is_never_sent_to_the_selected_chat
    build
    Master::Io::Chat.select_destination(service: "irc", target: "#help")
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, mode:| text }
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@refs, Struct.new(:renderer, :bus).new(renderer, nil))

    Master::Io::Chat.stub(:find, ->(service) { service == "irc" ? @irc : nil }) do
      output = capture_io { assert session.send(:route_active_chat, "/unknown hello") }.first
      assert_match(/not sent/, output)
      refute @io.written.any? { |line| line.start_with?("PRIVMSG #help") }
    end
  end

  def test_status_never_shows_the_password
    build(env: { "MASTER_IRC_PASSWORD" => "s3cret-pass" })
    assert_equal "CAP REQ :sasl", @io.written.first
    @io.feed(":srv CAP * ACK :sasl\r\n")
    assert eventually { @io.written.include?("AUTHENTICATE PLAIN") }
    @io.feed("AUTHENTICATE +\r\n")
    assert eventually { @io.written.any? { |l| l.start_with?("AUTHENTICATE ") && l != "AUTHENTICATE PLAIN" } }
    @io.feed(":srv 903 heyhey123 :ok\r\n")
    assert eventually { @io.written.include?("CAP END") }
    refute_includes [@irc.status, *@shown].join("\n"), "s3cret"
    refute_includes @io.written.join("\n"), "s3cret"
  end

  def test_tls_context_verifies_peer_and_hostname
    ctx = Irc.tls_context
    assert_equal OpenSSL::SSL::VERIFY_PEER, ctx.verify_mode
    assert ctx.verify_hostname
  end

  def test_command_parsing
    assert_equal ["irc.libera.chat", 6697], Irc.parse_target("irc.libera.chat")
    assert_equal ["irc.example.org", 6667], Irc.parse_target("irc.example.org:6667")
    assert_raises(ArgumentError) { Irc.parse_target("bad host!") }
    assert_equal "irc", Master::Io::Chat.service_for("irc.libera.chat heyhey123")
    assert_equal "telegram", Master::Io::Chat.service_for("telegram")
    reg = Master::CLI::CommandRegistry
    assert_equal "whatsapp0: not available yet", reg.dispatch_chat("connect", ctx: { args: "whatsapp" })
    build
    reg.chat_act(@irc, "join", "#a,#b #c", agent: nil)
    assert_equal ["JOIN #a", "JOIN #b", "JOIN #c"], @io.written.last(3)
    assert_match(/read-only/, reg.dispatch_chat_with(@irc, "say", "hi")) if reg.respond_to?(:dispatch_chat_with)
  end

  class Stub < Master::Io::Chat::Transport
    attr_reader :sent

    def name = "stub"
    def status = "stub0: up"
    def go(text) = emit(:message, room: "#r", nick: "n", text:)

    private

    def deliver(room, text, action: false) = (@sent ||= []) << [room, text]
  end

  # Every transport inherits sanitizing, read-only, and the event ring from the base.
  def test_shared_layer_applies_to_any_transport
    shown = []
    stub = Stub.new(out: ->(l) { shown << l }, policy: Policy.new(sleeper: ->(_s) {}))
    stub.go("hi\e[2J")
    assert_equal ["#r <n> hi"], shown
    assert_raises(Master::Io::Chat::ReadOnly) { stub.send_text("#r", "x") }
    stub.policy.speak = true
    stub.send_text("#r", "x")
    assert_equal [["#r", "x"]], stub.sent
    assert_equal 1, stub.events.size
  end

  def test_loopback_socket_registers_in_plain_text
    server = TCPServer.new("127.0.0.1", 0)
    lines = Queue.new
    Thread.new { c = server.accept; 2.times { lines << c.gets.chomp }; c.close }
    irc = Irc.new(out: ->(_l) {})
    irc.connect("127.0.0.1:#{server.addr[1]}", nick: "t1", plain: true)
    assert_equal "NICK t1", lines.pop
    irc.disconnect
  ensure
    server.close
  end
end

class TestChatIrcAutojoin < Minitest::Test
  # The channels named on /connect:irc are joined after 001, never before.
  def test_autojoin_after_welcome
    io = TestChatIrc::Duplex.new
    irc = Master::Io::Irc.new(connector: ->(_h, _p, tls:) { io }, env: {}, out: ->(_) {},
                              policy: Master::Io::Chat::Policy.new(bucket: Master::Io::Chat::Policy::Bucket.new(interval: 0.001, burst: 9), sleeper: ->(_) {}))
    irc.connect("irc.example.test", nick: "heyhey123", join: %w[#help #ruby])
    sleep 0.05
    refute(io.written.any? { |l| l.start_with?("JOIN") })
    io.feed(":srv 001 heyhey123 :welcome\r\n")
    20.times { break if io.written.count { |l| l.start_with?("JOIN") } >= 2; sleep 0.05 }
    assert_equal ["JOIN #help", "JOIN #ruby"], io.written.select { |l| l.start_with?("JOIN") }
    refute irc.policy.speak?
    irc.disconnect
  end
end
