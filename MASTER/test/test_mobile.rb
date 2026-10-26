# frozen_string_literal: true

require "test_helper"
require "socket"
require "mobile/bootstrap"
require "mobile/doctor"
require "mobile/face_client"
require "mobile/face_bridge_http"
require "mobile/host"
require "trace/effect_observer"

class TestMobileProfile < Minitest::Test
  def test_a_forced_profile_sets_the_defaults_the_operator_left_unset
    env = { "MASTER_PROFILE" => "mobile", "MASTER_WEB" => "1" }

    assert Master::Mobile::Profile.new(env:).activate!
    assert_equal "0", env["MASTER_BACKGROUND_SCAN"]
    assert_equal "1", env["MASTER_WEB"], "an operator's own setting stands"
  end

  def test_a_desktop_is_not_a_phone
    refute Master::Mobile::Profile.new(env: {}).activate!
  end

  def test_auto_approve_follows_the_data_until_the_operator_says_otherwise
    assert Master::Mobile::Profile.new(env: {}).auto_approve?
    refute Master::Mobile::Profile.new(env: { "MASTER_MOBILE_AUTO_APPROVE" => "0" }).auto_approve?
  end

  def test_every_profile_key_is_one_the_code_reads
    assert_equal %w[ambient bridge env face packages profile schema], Master::Mobile.config.keys.sort
  end
end

class TestMobileBootstrap < Minitest::Test
  class Auditor
    attr_reader :asked

    def pkg_install!(names)
      @asked = names
      Master::Mobile::AuditedExec::Observation.new(ok: true, detail: "installed")
    end
  end

  def phone(installed: [], **env)
    @auditor = Auditor.new
    Master::Mobile::Bootstrap.new(env: { "MASTER_PROFILE" => "mobile", **env }, auditor: @auditor,
                                  installed: ->(name) { installed.include?(name) })
  end

  def test_off_a_phone_it_skips
    result = Master::Mobile::Bootstrap.new(env: {}).ensure!

    assert result.ok
    assert_match(/not a phone/, result.messages.join)
  end

  def test_without_approval_it_names_the_command_and_installs_nothing
    result = phone("MASTER_MOBILE_AUTO_APPROVE" => "0").ensure!

    refute result.ok
    assert_includes result.missing, "clang"
    assert_nil @auditor.asked
  end

  def test_it_asks_pkg_for_the_pinned_names_only
    installed = %w[ruby git]
    result = phone(installed:).ensure!

    assert_equal %w[clang make libyaml openssl], @auditor.asked
    refute result.ok, "the fake pkg installed nothing, so the packages are still missing"
  end
end

class TestMobileAuditedExec < Minitest::Test
  class Bus
    attr_reader :events

    def initialize(down: nil)
      @down = down
      @events = []
    end

    def publish_required(name, payload)
      raise IOError, "bus down" if name == @down

      @events << [name, payload]
    end
  end

  def auditor(bus, runner)
    observer = Master::Trace::EffectObserver.new(bus:, run_id: "run-mobile-1")
    Master::Mobile::AuditedExec.new(observer:, run_id: "run-mobile-1", runner:)
  end

  def test_the_envelope_carries_a_digest_not_the_package_list
    bus = Bus.new
    ran = []

    assert auditor(bus, ->(argv) { ran << argv }).pkg_install!(%w[ruby git]).ok?
    assert_equal [%w[pkg install -y ruby git]], ran
    _name, payload = bus.events.first

    assert payload[:scope_digest]
    refute_includes payload.to_s, "ruby"
  end

  def test_a_lost_before_event_installs_nothing
    bus = Bus.new(down: Master::Trace::EffectObserver::BEFORE_EVENT)
    ran = []
    observation = auditor(bus, ->(argv) { ran << argv }).pkg_install!(%w[ruby])

    refute observation.ok?
    assert_empty ran
    assert_match(/before-event/, observation.message)
  end
end

class TestMobileFace < Minitest::Test
  def with_server(on_utterance: nil)
    Dir.mktmpdir("face") do |dir|
      server = Master::Mobile::FaceServer.new(root: dir, run_id: "face-1", on_utterance:,
                                              socket_path: File.join(dir, "face.sock"))
      server.start!
      thread = Thread.new { server.serve_once }
      yield server
    ensure
      thread&.kill
      server&.stop!
    end
  end

  def test_hello_then_ping_round_trip
    with_server do |server|
      client = Master::Mobile::FaceClient.new(socket_path: server.socket_path).connect!

      assert_equal "pong", client.ping["type"]
      client.close
    end
  end

  def test_an_utterance_is_answered_with_say
    with_server(on_utterance: ->(text, _source) { "heard #{text}" }) do |server|
      client = Master::Mobile::FaceClient.new(socket_path: server.socket_path).connect!

      assert_equal "heard hi", client.utterance("hi")["text"]
      client.close
    end
  end

  def test_a_live_socket_is_not_deleted_as_stale
    with_server do |server|
      second = Master::Mobile::FaceServer.new(root: Dir.tmpdir, socket_path: server.socket_path)

      assert_raises(RuntimeError) { second.start! }
    end
  end
end

class TestMobileHost < Minitest::Test
  Reply = Data.define(:ok, :output, :error) do
    def ok? = ok
  end

  class Bridge
    attr_reader :prompts

    def initialize = @prompts = []

    def submit_utterance!(prompt)
      @prompts << prompt
      Reply.new(ok: true, output: "fine\n", error: nil)
    end
  end

  class Ears
    def initialize(text) = @text = text
    def listen_once = Master::Mobile::Ambient::Result.new(ok: true, text: @text, error: nil)
    def speak!(text) = Master::Mobile::Ambient::Result.new(ok: true, text:, error: nil)
  end

  def host(dir, heard: "")
    ENV["MASTER_MEMORY_PATH"] = File.join(dir, "memory.yml")
    @bridge = Bridge.new
    Master::Mobile::Host.new(root: dir, bridge: @bridge, ambient: Ears.new(heard))
  ensure
    ENV.delete("MASTER_MEMORY_PATH")
  end

  def test_a_second_utterance_carries_the_first_and_the_name
    Dir.mktmpdir do |dir|
      phone = host(dir)
      phone.handle_utterance("call me Johann")
      phone.handle_utterance("what time is it")

      assert_includes @bridge.prompts.last, "name: Johann"
      assert_includes @bridge.prompts.last, "user: call me Johann"
      refute_includes @bridge.prompts.first, "Recent turns", "the first utterance has no history"
    end
  end

  def test_one_press_of_listen_hears_answers_and_speaks
    Dir.mktmpdir do |dir|
      answer = host(dir, heard: "hello").listen_and_answer

      assert_equal({ "ok" => true, "heard" => "hello", "reply" => "fine", "spoken" => true }, answer)
    end
  end

  def test_silence_is_not_sent_to_master
    Dir.mktmpdir do |dir|
      refute host(dir).listen_and_answer["ok"]
      assert_empty @bridge.prompts
    end
  end
end

class TestMobileBridgeHttp < Minitest::Test
  def app(dir)
    ENV["MASTER_MEMORY_PATH"] = File.join(dir, "memory.yml")
    host = Master::Mobile::Host.new(root: dir, bridge: TestMobileHost::Bridge.new,
                                    ambient: TestMobileHost::Ears.new(""))
    Master::Mobile::FaceBridgeHttp.new(root: dir, host:)
  ensure
    ENV.delete("MASTER_MEMORY_PATH")
  end

  def test_the_face_page_and_its_script_are_served
    Dir.mktmpdir do |dir|
      status, headers, = app(dir).call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/face")

      assert_equal 200, status
      assert_match(/html/, headers["content-type"])
      assert_equal 200, app(dir).call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/face_bridge.js").first
    end
  end

  def test_an_utterance_posts_through_to_the_host
    Dir.mktmpdir do |dir|
      input = StringIO.new(JSON.generate("text" => "hi"))
      status, _headers, body = app(dir).call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/utterance",
                                             "rack.input" => input)

      assert_equal 200, status
      assert_equal "fine", JSON.parse(body.join)["reply"]
    end
  end

  def test_the_bind_is_loopback
    assert_equal "127.0.0.1", Master::Mobile.config.dig("bridge", "bind")
  end
end

class TestMobileDoctor < Minitest::Test
  def test_a_desktop_without_termux_packages_is_not_ready
    Dir.mktmpdir do |dir|
      report = Master::Mobile::Doctor.new(root: dir).report

      assert_includes %w[ready blocked], report["status"]
      assert_equal report["blocked_by"].empty?, report["status"] == "ready"
    end
  end
end
