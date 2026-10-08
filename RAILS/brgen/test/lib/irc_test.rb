# frozen_string_literal: true

require "test_helper"

class BrgenIrcMessageTest < ActiveSupport::TestCase
  M = Brgen::Irc::Message

  test "parses a command with a spaced trailing param" do
    m = M.parse("PRIVMSG #brgen :hello there world\r\n")
    assert_equal "PRIVMSG", m.command
    assert_equal "#brgen", m.params.first
    assert_equal "hello there world", m.params.last
  end

  test "parses a command with no trailing" do
    m = M.parse("NICK alice")
    assert_equal "NICK", m.command
    assert_equal [ "alice" ], m.params
  end

  test "parses a prefix" do
    m = M.parse(":alice!a@host JOIN #brgen")
    assert_equal "alice!a@host", m.prefix
    assert_equal "JOIN", m.command
  end

  test "build colon-quotes only a spaced last param" do
    assert_equal "PONG :a b", M.build("PONG", [ "a b" ])
    assert_equal "JOIN #brgen", M.build("JOIN", [ "#brgen" ])
    assert_equal ":srv 353 me = #brgen :@master +echo", M.build("353", [ "me", "=", "#brgen", "@master +echo" ], prefix: "srv")
  end
end

class BrgenIrcSessionTest < ActiveSupport::TestCase
  Chan = Struct.new(:slug)

  class FakeBridge
    attr_reader :posts
    attr_accessor :relay

    def initialize
      @posts = []
      @relay = []
      @next_id = 100
    end

    def channel_for(name)
      slug = name.to_s.sub(/\A#/, "")
      %w[brgen marketplace].include?(slug) ? Chan.new(slug) : nil
    end

    def channel_name(chan) = "##{chan.slug}"
    def topic(_chan) = "the lobby"
    def history(_chan, **) = [ { id: 1, nick: "master", text: "welcome" } ]
    def roster(_chan) = [ { nick: "master", mode: "@" }, { nick: "echo", mode: "+" } ]
    def messages_since(_chan, last) = @relay.select { |m| m[:id] > last }

    def post(chan, nick, text)
      @posts << { slug: chan.slug, nick: nick, text: text }
      Struct.new(:id).new(@next_id += 1)
    end
  end

  def setup
    @bridge = FakeBridge.new
    @session = Brgen::Irc::Session.new(bridge: @bridge, server_name: "srv")
  end

  def register!
    @session.handle("NICK alice")
    @session.handle("USER alice 0 * :Alice")
  end

  test "NICK + USER completes registration with the welcome numerics" do
    assert_empty @session.handle("NICK alice")
    out = @session.handle("USER alice 0 * :Alice")
    assert @session.registered?
    assert(out.any? { |l| l.include?(" 001 ") && l.include?("alice") })
    assert(out.any? { |l| l.include?(" 376 ") })
  end

  test "JOIN a known channel returns JOIN, topic, NAMES with modes, and history" do
    register!
    out = @session.handle("JOIN #brgen")
    assert(out.any? { |l| l.start_with?(":alice!alice@brgen JOIN #brgen") })
    assert(out.any? { |l| l.include?(" 332 ") && l.include?("the lobby") })
    assert(out.any? { |l| l.include?(" 353 ") && l.include?("@master") && l.include?("+echo") })
    assert(out.any? { |l| l.include?(" 366 ") })
    assert(out.any? { |l| l.start_with?(":master PRIVMSG #brgen :welcome") })
  end

  test "JOIN an unknown channel returns 403" do
    register!
    out = @session.handle("JOIN #nope")
    assert(out.any? { |l| l.include?(" 403 ") })
  end

  test "PRIVMSG posts to the bridge and does not echo back" do
    register!
    @session.handle("JOIN #brgen")
    out = @session.handle("PRIVMSG #brgen :hei alle")
    assert_empty out, "IRC never echoes your own PRIVMSG"
    assert_equal [ { slug: "brgen", nick: "alice", text: "hei alle" } ], @bridge.posts
  end

  test "poll relays web-side messages but not the client's own nick" do
    register!
    @session.handle("JOIN #brgen")
    @bridge.relay = [ { id: 2, nick: "bob", text: "from the web" }, { id: 3, nick: "alice", text: "mine" } ]
    out = @session.poll
    assert(out.any? { |l| l == ":bob PRIVMSG #brgen :from the web" })
    assert(out.none? { |l| l.include?(":alice PRIVMSG") })
  end

  test "PING gets a PONG" do
    register!
    assert(@session.handle("PING :srv").any? { |l| l.start_with?(":srv PONG") })
  end
end
