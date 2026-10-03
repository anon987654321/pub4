# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
require "yaml"

# The lifecycle scripts in bin/, run as processes. Each script resolves its
# paths from its own location, so a copy under a temporary MASTER/ directory
# writes into that directory and never into the checkout.
class TestBinScripts < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_doctor_reports_ok_fail_lines
    output, = Open3.capture3({ "MASTER_KEYLESS" => "1" }, RbConfig.ruby, File.join(ROOT, "bin", "doctor"), chdir: ROOT)

    assert_includes output, "MASTER doctor"
    assert_match(/^(?:OK|FAIL) yaml:/, output)
    assert_match(/^OK (?:ruby|git):/, output)
  end

  def test_cleanup_refuses_a_dirty_tree
    Dir.mktmpdir do |repo|
      script = cleanup_fixture(repo)
      File.write(File.join(repo, "untracked.txt"), "x")

      out, status = Open3.capture2e(RbConfig.ruby, script, chdir: repo)

      refute status.success?
      assert_includes out, "working tree dirty"
    end
  end

  def test_cleanup_is_a_dry_run_by_default_and_writes_its_reports
    Dir.mktmpdir do |repo|
      script = cleanup_fixture(repo)

      out, status = Open3.capture2e(RbConfig.ruby, script, chdir: repo)

      assert status.success?, out
      assert_includes out, "test_shot.jpg"
      assert File.exist?(File.join(repo, "test_shot.jpg")), "a dry run deleted a candidate"
      reports = Dir.children(File.join(repo, "MASTER", "reports", "cleanup"))
      assert(reports.any? { |name| name.start_with?("inventory_before.json") })
      assert(reports.any? { |name| name.start_with?("history_before.txt") })
    end
  end

  def test_cleanup_apply_removes_the_candidates
    Dir.mktmpdir do |repo|
      script = cleanup_fixture(repo)

      out, status = Open3.capture2e(RbConfig.ruby, script, "--apply", chdir: repo)

      assert status.success?, out
      refute File.exist?(File.join(repo, "test_shot.jpg"))
    end
  end

  def test_smoke_web_passes_against_a_ready_face
    with_fake_face(ready: true) do |url|
      out, status = run_smoke_web(url)

      assert status.success?, out
      assert_includes out, "wait for bootstrap"
      assert_match(/state=clean checks=\d+/, out)
    end
  end

  def test_smoke_web_fails_on_a_warming_face
    with_fake_face(ready: false) do |url|
      out, status = run_smoke_web(url)

      refute status.success?, out
      assert_includes out, "warming page"
    end
  end

  def test_smoke_web_skips_when_nothing_listens
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }

    out, status = run_smoke_web("http://127.0.0.1:#{port}")

    assert status.success?, out
    assert_includes out, "reason=not_listening"
  end

  private

  def copy_script(repo, name)
    bin = File.join(repo, "MASTER", "bin")
    FileUtils.mkdir_p(bin)
    FileUtils.cp(File.join(ROOT, "bin", name), bin)
    File.join(bin, name)
  end

  def cleanup_fixture(repo)
    script = copy_script(repo, "cleanup")
    File.write(File.join(repo, ".gitignore"), "MASTER/reports/\n")
    File.write(File.join(repo, "test_shot.jpg"), "jpg")
    git(repo, "init", "-q")
    git(repo, "add", ".")
    git(repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "fixture")
    script
  end

  def git(repo, *argv)
    _, status = Open3.capture2e("git", "-C", repo, *argv)
    assert status.success?, "git #{argv.join(' ')} failed in the fixture"
  end

  def run_smoke_web(url)
    env = {
      "MASTER_WEB_URL" => url, "PROBE_TOKEN" => "t" * 43,
      "MASTER_SMOKE_WEB_WARM_S" => "1", "MASTER_SMOKE_WEB_POLL_S" => "1", "MASTER_SMOKE_WEB_READ_S" => "5"
    }
    Open3.capture2e(env, RbConfig.ruby, File.join(ROOT, "bin", "smoke-web"))
  end

  # A face that answers every path smoke-web asks for, either booted or still
  # showing the warming page.
  def with_fake_face(ready:)
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      loop do
        client = server.accept
        request = client.gets.to_s
        headers = {}
        while (line = client.gets) && line != "\r\n"
          key, value = line.split(":", 2)
          headers[key.downcase] = value.to_s.strip
        end
        client.write(response_for(request.split[1].to_s, headers, ready:))
        client.close
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET
        next
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}"
  ensure
    thread&.kill
    server&.close
  end

  def response_for(path, headers, ready:)
    case path
    when "/up" then http(200, "ok")
    when %r{\A/chat/message} then http(200, ready ? "pong" : "Starting up")
    when "/" then http(200, ready ? '<canvas id="face"></canvas><script>ensurePrimer()</script>' : "Starting up")
    when "/master_events.js", "/shortcut_sheet.js" then http(200, "//")
    when "/chat/metrics" then metrics(headers)
    when "/events/stream" then http(200, "data: {}\n\n", type: "text/event-stream")
    else http(404, "")
    end
  end

  def metrics(headers)
    return http(401, "{}") unless headers["x-token"]

    keys = %w[model tokens uptime open_breakers cache_efficiency model_quota]
    http(200, JSON.generate(keys.to_h { |key| [key, 0] }), type: "application/json")
  end

  def http(code, body, type: "text/html")
    "HTTP/1.1 #{code} X\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  end
end
