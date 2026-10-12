# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "support_fake_http"
require_relative "../lib/io/chat/slskd"

class ChatSlskdTest < Minitest::Test
  Chat = Master::Io::Chat
  KEY = "k3y-SECRET-apikey"
  PASS = "pass-SECRET-word"
  FILES = [
    { "filename" => "\\\\u\\music\\Track \e[31mOne\e[0m.flac", "size" => 30_000_000, "bitRate" => 900 },
    { "filename" => "\\\\u\\music\\virus.exe", "size" => 1000, "bitRate" => nil },
    { "filename" => "\\\\u\\music\\huge.wav", "size" => 900_000_000 },
    { "filename" => "\\\\u\\music\\ok.mp3", "size" => 4_000_000, "bitRate" => 320 }
  ].freeze

  def setup
    @tmp = Dir.mktmpdir("slsk")
    @lines = []
    @searches = 0
    @server = FakeHttp.new { |req| route(req) }
    @msgs = [{ "timestamp" => "t1", "username" => "bob\e[2J", "message" => "hello‮" }]
  end

  def teardown
    @server.stop
    FileUtils.remove_entry(@tmp)
  end

  def route(req)
    path = req.path.split("?").first
    if path == "/api/v0/session"
      return [200, { "token" => "jwt-SECRET-token" }] if req.json == { "username" => "me", "password" => PASS }

      return [401, nil]
    end
    return [401, nil] unless req.headers["x-api-key"] == KEY || req.headers["authorization"] == "Bearer jwt-SECRET-token"

    case [req.verb, path]
    in ["GET", "/api/v0/application"] then [200, { "version" => "0.22\e[1m", "server" => { "state" => "Connected, LoggedIn" } }]
    in ["POST", "/api/v0/searches"] then [200, { "id" => req.json["id"] }]
    in ["GET", %r{\A/api/v0/searches/[^/]+\z}] then (@searches += 1) < 2 ? [200, { "isComplete" => false }] : [200, { "isComplete" => true }]
    in ["GET", %r{/responses\z}] then [200, [{ "username" => "u\e[2Jser", "uploadSpeed" => 2_097_152, "files" => FILES }]]
    in ["GET", "/api/v0/rooms/joined"] then [200, ["techno"]]
    in ["GET", "/api/v0/rooms/joined/techno/messages"] then [200, @msgs]
    in ["POST", "/api/v0/rooms/joined"] then [201, {}]
    in ["POST", "/api/v0/rooms/joined/techno/messages"] then [201, nil]
    in ["GET", "/api/v0/conversations"] then [200, [{ "username" => "ann" }]]
    in ["GET", "/api/v0/conversations/ann/messages"] then [200, [{ "timestamp" => "t9", "username" => "ann", "message" => "psst" }]]
    in ["POST", "/api/v0/conversations/ann"] then [201, nil]
    in ["POST", "/api/v0/transfers/downloads/batches"] then [200, {}]
    in ["GET", "/api/v0/transfers/downloads"]
      [200, [{ "username" => "u", "directories" => [{ "files" => [{ "filename" => "a\\b.flac", "state" => "InProgress", "percentComplete" => 41.6 }] }] }]]
    in ["GET", "/api/v0/users/u/browse"] then [200, [{ "name" => "music\e[2J", "files" => [1, 2, 3] }]]
    else [404, nil]
    end
  end

  def env(extra = {})
    { "MASTER_SLSKD_URL" => @server.url, "MASTER_SLSKD_API_KEY" => KEY, "MASTER_SLSK_DIR" => File.join(@tmp, "slsk/incoming") }.merge(extra)
  end

  def transport(extra = {})
    t = Chat::Slskd.new(env: env(extra), out: ->(l) { @lines << l }, sleeper: ->(_) {},
                        policy: Chat::Policy.new(bucket: Chat::Policy::Bucket.new(interval: 0.0001, burst: 100), sleeper: ->(_) {}))
    t.connect
    @lines.clear
    t
  end

  def test_remote_urls_refused
    assert_raises(Chat::Slskd::Client::Refused) { Chat::Slskd::Client.new(env: { "MASTER_SLSKD_URL" => "http://example.com:5030", "MASTER_SLSKD_API_KEY" => "k" }) }
    assert_raises(Chat::Slskd::Client::Refused) { Chat::Slskd::Client.new(env: { "MASTER_SLSKD_URL" => "http://example.com", "MASTER_SLSKD_ALLOW_REMOTE" => "1" }) }
    assert_raises(Chat::Slskd::Client::Refused) { Chat::Slskd::Client.new(env: { "MASTER_SLSKD_URL" => "file:///etc/passwd" }) }
    assert Chat::Slskd::Client.new(env: { "MASTER_SLSKD_URL" => "https://box.example.com", "MASTER_SLSKD_ALLOW_REMOTE" => "1" })
    assert Chat::Slskd::Client.new(env: { "MASTER_SLSKD_URL" => "http://localhost:5030" })
  end

  def test_api_key_auth_and_status_hides_secrets
    t = Chat::Slskd.new(env: env, out: ->(l) { @lines << l })
    t.connect
    text = (@lines + [t.status]).join("\n")
    refute_includes text, KEY
    assert_includes text, "auth api-key"
    refute_match(/\e/, text)
  end

  def test_missing_or_wrong_key_error_has_no_secret
    t = Chat::Slskd.new(env: env("MASTER_SLSKD_API_KEY" => "wrong-SECRET-key"), out: ->(_) {})
    err = assert_raises(Chat::Slskd::Unavailable) { t.connect }
    refute_includes err.message, "wrong-SECRET"
    t2 = Chat::Slskd.new(env: env("MASTER_SLSKD_API_KEY" => ""), out: ->(_) {})
    assert_raises(Chat::Slskd::Unavailable) { t2.connect }
  end

  def test_session_login_uses_jwt
    t = Chat::Slskd.new(env: env("MASTER_SLSKD_API_KEY" => nil, "MASTER_SLSKD_USERNAME" => "me", "MASTER_SLSKD_PASSWORD" => PASS), out: ->(l) { @lines << l })
    t.connect
    assert(@server.requests.any? { |r| r.headers["authorization"] == "Bearer jwt-SECRET-token" })
    refute_includes @lines.join, "jwt-SECRET"
    refute_includes t.status, PASS
  end

  def test_search_numbers_and_strips_hostile_text
    t = transport
    lines = t.command("search deep house")
    text = lines.join("\n")
    refute_match(/\e/, text)
    assert_includes text, "[1] 28.6MB 900k"
    assert_includes text, "Track One.flac"
    assert_equal 4, t.results.size
  end

  def test_get_vets_extension_and_size_and_no_auto_download
    t = transport
    t.command("search x")
    assert_empty(@server.requests.select { |r| r.path.include?("transfers") }, "search must not download")
    assert_match(/not allowed/, t.command("get 2").join)
    assert_match(/over the 300.0 MB cap/, t.command("get 3").join)
    assert_empty(@server.requests.select { |r| r.verb == "POST" && r.path.include?("transfers") })
    out = t.command("get 4").join("\n")
    assert_includes out, "queued ok.mp3"
    assert_includes out, "not opened"
    post = @server.requests.find { |r| r.path.include?("batches") }
    assert_equal "ok.mp3", post.json["files"][0]["filename"].split("\\").last
  end

  def test_get_accepts_one_plain_number_only
    t = transport
    t.command("search x")
    ["", "all", "*", "1-4", "1 2", "1,2", "-1", "0", "9"].each do |arg|
      assert_match(/slsk0: /, t.command("get #{arg}").join)
    end
    assert_empty(@server.requests.select { |r| r.verb == "POST" && r.path.include?("transfers") })
  end

  def test_notice_once_and_quarantine_0700
    t = transport
    t.command("search x")
    first = t.command("get 1").join("\n")
    assert_includes first, "unlicensed"
    assert_equal "700", format("%o", File.stat(t.quarantine.dir).mode & 0o777)
    second = t.command("get 4").join("\n")
    refute_includes second, "unlicensed"
  end

  def test_quarantine_outside_repo_and_inside_refused
    q = Chat::Slskd::Quarantine.new(env: { "MASTER_SLSK_DIR" => File.join(@tmp, "x") })
    refute q.dir.start_with?(Chat::Slskd::Quarantine::REPO_ROOT)
    inside = Chat::Slskd::Quarantine.new(env: { "MASTER_SLSK_DIR" => File.join(Chat::Slskd::Quarantine::REPO_ROOT, "MASTER/output/slsk") })
    assert_raises(Chat::Slskd::Quarantine::Refused) { inside.prepare! }
    default = Chat::Slskd::Quarantine.new(env: {})
    assert_match(%r{/\.master/slsk/incoming\z}, default.dir)
    assert_equal 300 * 1024 * 1024, default.max_bytes
  end

  def test_extension_allowlist
    q = Chat::Slskd::Quarantine.new(env: {})
    %w[wav flac aiff mp3 ogg m4a opus].each { |e| assert q.vet!("a\\b.#{e.upcase}", 10) }
    %w[exe zip lnk sh js mp3.exe].each { |e| assert_raises(Chat::Slskd::Quarantine::Refused) { q.vet!("a.#{e}", 10) } }
    assert_raises(Chat::Slskd::Quarantine::Refused) { q.vet!("a.mp3", nil) }
  end

  def test_read_only_blocks_say_and_speak_on_sends
    t = transport
    assert_raises(Chat::ReadOnly) { t.send_text("room:techno", "hi") }
    assert_raises(Chat::ReadOnly) { t.send_text("pm:ann", "hi") }
    t.policy.speak = true
    t.send_text("room:techno", "hi")
    t.send_text("pm:ann", "hi")
    assert_raises(ArgumentError) { t.send_text("techno", "hi") }
    posts = @server.requests.select { |r| r.verb == "POST" && r.path =~ /messages|conversations/ }
    assert_equal 2, posts.size
  end

  def test_rooms_and_conversations_read_sanitized_and_deduped
    t = transport
    assert_equal 2, t.poll_once
    text = @lines.join("\n")
    assert_includes text, "techno <bob> hello"
    assert_includes text, "pm:ann"
    refute_match(/[\e‮]/, text)
    assert_equal 0, t.poll_once
    @msgs << { "timestamp" => "t2", "username" => "cy", "message" => "new" }
    assert_equal 1, t.poll_once
  end

  def test_queue_browse_join_leave
    t = transport
    assert_includes t.command("queue").join, "b.flac InProgress 42%"
    browse = t.command("browse u").join("\n")
    assert_includes browse, "music (3 files)"
    refute_match(/\e/, browse)
    assert_equal "joined techno", t.join("techno")
  end

  def test_no_share_config_endpoints_touched
    t = transport
    t.command("search x")
    t.command("queue")
    refute(@server.requests.any? { |r| r.path =~ %r{/options|/shares} })
  end

  def test_unknown_command_prints_usage
    assert_includes transport.command("bogus").join, "usage"
  end
end
