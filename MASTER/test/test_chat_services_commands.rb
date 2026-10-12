# frozen_string_literal: true

require "test_helper"
require_relative "support_fake_http"

# /connect telegram|slskd, /slsk and /say through the real command registry,
# against local fake servers only.
class ChatServicesCommandsTest < Minitest::Test
  Chat = Master::Io::Chat
  REG = Master::CLI::CommandRegistry
  TOKEN = "777000:REGISTRYsecretTOKEN123"

  def setup
    @saved = ENV.to_h.slice("MASTER_TELEGRAM_TOKEN", "MASTER_SLSKD_URL", "MASTER_SLSKD_API_KEY", "MASTER_CLI_QUIET")
    @sent = []
    @tg = FakeHttp.new do |req|
      case req.path.split("/").last
      when "getMe" then [200, { ok: true, result: { username: "mbot" } }]
      when "getUpdates" then sleep 0.05; [200, { ok: true, result: [] }]
      when "sendMessage" then (@sent << req.json; [200, { ok: true, result: {} }])
      end
    end
    @rooms = []
    @sk = FakeHttp.new do |req|
      @rooms << req.json if req.verb == "POST" && req.path.end_with?("/rooms/joined")
      req.path.end_with?("/application") ? [200, { "version" => "1" }] : [200, []]
    end
    ENV["MASTER_CLI_QUIET"] = "1"
  end

  def teardown
    %w[telegram slskd].each { |s| Chat.find(s)&.disconnect; Chat.forget(s) }
    @tg.stop
    @sk.stop
    %w[MASTER_TELEGRAM_TOKEN MASTER_SLSKD_URL MASTER_SLSKD_API_KEY MASTER_CLI_QUIET].each { |k| ENV.delete(k) }
    @saved.each { |k, v| ENV[k] = v }
  end

  def run_cmd(verb, args = "") = REG.dispatch_chat(verb, ctx: { args: })

  def test_telegram_connect_without_token_says_so
    ENV.delete("MASTER_TELEGRAM_TOKEN")
    assert_match(/telegram0: .*not set/, run_cmd("connect", "telegram"))
  end

  def test_slskd_connect_refuses_remote_and_slsk_needs_connection
    assert_equal "slsk0: not connected; /connect slskd", run_cmd("slsk", "status")
    ENV["MASTER_SLSKD_URL"] = "http://example.com:5030"
    ENV["MASTER_SLSKD_API_KEY"] = "k"
    assert_match(/slskd0: .*not on localhost/, run_cmd("connect", "slskd"))
  end

  def test_slskd_connect_status_and_read_only_say
    ENV["MASTER_SLSKD_URL"] = @sk.url
    ENV["MASTER_SLSKD_API_KEY"] = "key-SECRETvalue"
    out = run_cmd("connect", "slskd")
    assert_includes out, "slsk0: slskd attached read-only"
    refute_includes out, "SECRET"
    assert_match(/results 0/, run_cmd("slsk", "status"))
    assert_match(/read-only/, run_cmd("say", "room:x hi"))
    assert_match(/usage/, run_cmd("slsk", "nonsense"))
  end

  def test_telegram_say_is_gated_then_goes_to_explicit_chat
    ENV["MASTER_TELEGRAM_TOKEN"] = TOKEN
    Chat.transport("telegram").tap { |t| t.instance_variable_set(:@http, Chat::Http.new(base: @tg.url, secrets: -> { [TOKEN] })) }
    assert_includes run_cmd("connect", "telegram"), "telegram"
    out = run_cmd("say", "12345 hello")
    assert_match(/read-only/, out)
    assert_empty @sent
    run_cmd("chat", "speak on")
    run_cmd("say", "12345 hello")
    assert_equal [{ "chat_id" => "12345", "text" => "hello" }], @sent
    refute_includes run_cmd("chat", "status"), "REGISTRYsecret"
    assert_match(/not available/, run_cmd("topic", "x"))
  end

  def test_connect_slsk_joins_rooms_and_labels_nick
    ENV["MASTER_SLSKD_URL"] = @sk.url
    ENV["MASTER_SLSKD_API_KEY"] = "key-SECRETvalue"
    out = run_cmd("connect:slsk", "heyhey123 #indie #punk")
    assert_equal %w[indie punk], @rooms
    assert_includes out, "slsk0: slskd attached read-only"
    assert_equal "heyhey123", Chat.find("slskd").nick
    refute_includes out, "SECRET"
    assert_match(/read-only/, run_cmd("say", "room:indie hi"))
  end

  def test_connect_slsk_rooms_only_and_bad_room
    ENV["MASTER_SLSKD_URL"] = @sk.url
    ENV["MASTER_SLSKD_API_KEY"] = "k"
    assert_match(/not a room/, run_cmd("connect:slsk", "nick #a,b"))
    run_cmd("connect:slsk", "#solo")
    assert_equal %w[solo], @rooms
    assert_equal "slskd", Chat.find("slskd").nick
  end

  def test_connect_slsk_remote_refused
    ENV["MASTER_SLSKD_URL"] = "http://example.com"
    ENV["MASTER_SLSKD_API_KEY"] = "k"
    assert_match(/slsk0: .*not on localhost/, run_cmd("connect:slsk", "nick #a"))
  end

  def test_connect_telegram_form
    ENV.delete("MASTER_TELEGRAM_TOKEN")
    assert_match(/not set/, run_cmd("connect:telegram"))
    assert_match(/takes no arguments/, run_cmd("connect:telegram", "#x"))
    assert_match(/unknown protocol/, run_cmd("connect:wat", "x"))
  end

  def test_connect_irc_form_validates_before_connecting
    assert_match(/not a channel: nochan/, run_cmd("connect:irc", "irc.example.test nick nochan"))
    assert_match(/which nick/, run_cmd("connect:irc", ""))
  end

  def test_registry_has_one_entry_per_form_and_intake_parses_colon
    %w[connect connect:irc connect:slsk connect:telegram].each { |v| assert_includes REG::CHAT_VERBS, v }
    m = "/connect:irc irc.libera.chat heyhey123 #help".match(Master::CLI::Stages::Intake::COMMAND_RE)
    assert_equal "connect:irc", m[1]
    assert_equal "irc.libera.chat heyhey123 #help", m[2].strip
    assert_includes REG.help_text("connect:slsk"), "label"
  end
end
