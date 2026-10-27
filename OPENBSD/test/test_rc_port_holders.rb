# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

# The web rc.d scripts need OpenBSD's rc.subr, so they cannot run whole here.
# Their port-holder helpers sit between two marker lines and are plain ksh; this
# runs exactly that text against a stubbed fstat(1) whose output is the shape
# vm23 prints, with kill, logger and sleep recorded instead of acting.

# What it proves: a free port starts without a signal, a listener under any argv
# is found and TERMed, one that survives TERM gets KILL, a port that never frees
# refuses the start, and relayd's connections to the port are never taken for a
# holder.
class RcPortHoldersTest < Minitest::Test
  RC_D = File.expand_path("../etc/rc.d", __dir__)
  APPS = %w[brgen amber bsdports master].freeze
  MARKERS = /^# port holders: begin$.*?^# port holders: end$/m
  PORT = 38_182
  FALCON = 71_359
  WORKER = 76_198
  RELAYD = 4_455
  OTHER = 97_216

  def helpers(app)
    File.read(File.join(RC_D, app), encoding: "UTF-8")[MARKERS]
  end

  def socket(user, pid, local, peer: nil)
    [user, "ruby34", pid, "7*", "internet", "stream", "tcp", "0x0", local, peer].compact.join(" ")
  end

  # The falcon parent and its retitled worker both hold the listener; relayd's
  # connection, the accepted side and another port's listener must not count.
  def listening
    rows = [
      "USER CMD PID FD MOUNT INUM MODE R/W SZ|DV",
      socket("_relayd", RELAYD, "127.0.0.1:16148", peer: "--> 127.0.0.1:#{PORT}"),
      socket("brgen", WORKER, "127.0.0.1:#{PORT}"),
      socket("brgen", WORKER, "127.0.0.1:#{PORT}", peer: "<-- 127.0.0.1:16148"),
      socket("brgen", FALCON, "127.0.0.1:#{PORT}"),
      socket("irc", OTHER, "127.0.0.1:9999"),
    ]

    rows.join("\n") << "\n"
  end

  def connected_only
    rows = [
      socket("_relayd", RELAYD, "127.0.0.1:16148", peer: "--> 127.0.0.1:#{PORT}"),
      socket("irc", OTHER, "127.0.0.1:9999"),
    ]

    rows.join("\n") << "\n"
  end

  # survive: the signals the holders outlive, e.g. "TERM" or "TERM KILL".
  def run_free(dir, fstat:, survive: "", app: "brgen")
    File.write(File.join(dir, "fstat.out"), fstat)
    stub = File.join(dir, "fstat")
    File.write(stub, "#!/bin/sh\ncat #{dir}/fstat.out\n")
    File.chmod(0o755, stub)

    script = <<~SH
      PATH=#{dir}:$PATH; PORT=#{PORT}; PORT_OWNER=#{app}
      sleep() { :; }
      logger() { echo "logger $*" >> #{dir}/calls; }
      kill() {
        echo "kill $*" >> #{dir}/calls
        case " #{survive} " in *" ${1#-} "*) ;; *) : > #{dir}/fstat.out ;; esac
      }
      #{helpers(app)}
      free_port; echo "exit=$?"
    SH
    out = IO.popen(["ksh", "-c", script, { err: %i[child out] }], &:read)
    calls_file = File.join(dir, "calls")
    [out, File.exist?(calls_file) ? File.read(calls_file) : ""]
  end

  def test_every_web_script_carries_the_same_helpers
    APPS.each { |app| refute_nil helpers(app), "rc.d/#{app} lost its port-holder markers" }

    assert_equal 1, APPS.map { |app| helpers(app) }.uniq.size, "the four copies drifted apart"
  end

  def test_every_web_script_frees_its_port_in_rc_pre
    APPS.each do |app|
      rc_pre = File.read(File.join(RC_D, app), encoding: "UTF-8")[/^rc_pre\(\) \{.*?^\}/m]

      assert_match(/PORT_OWNER=#{app}\n\s*free_port \|\|/, rc_pre, "rc.d/#{app} rc_pre must call free_port")
    end
  end

  def test_every_curl_probe_is_bounded
    APPS.each do |app|
      File.read(File.join(RC_D, app), encoding: "UTF-8").each_line.grep(/^\s*curl /).each do |line|
        assert_match(/ -m \d+ /, line, "rc.d/#{app}: an unbounded curl can hang rc — #{line.strip}")
      end
    end
  end

  def test_a_free_port_sends_no_signal
    Dir.mktmpdir do |dir|
      out, calls = run_free(dir, fstat: connected_only)

      assert_equal "exit=0\n", out
      assert_empty calls, "relayd's connection to the port is not a holder"
    end
  end

  def test_every_listener_is_termed_whatever_its_argv
    Dir.mktmpdir do |dir|
      out, calls = run_free(dir, fstat: listening)

      assert_equal "exit=0\n", out
      assert_includes calls, "kill -TERM #{WORKER}"
      refute_match(/#{RELAYD}|#{OTHER}/, calls, "only the listeners on this port are signalled")
      refute_match(/-KILL/, calls)
    end
  end

  def test_a_holder_that_survives_term_is_killed
    Dir.mktmpdir do |dir|
      out, calls = run_free(dir, fstat: listening, survive: "TERM")

      assert_equal "exit=0\n", out
      assert_includes calls, "kill -TERM #{FALCON}"
      assert_includes calls, "kill -KILL #{WORKER}"
    end
  end

  def test_a_port_that_never_frees_refuses_the_start
    Dir.mktmpdir do |dir|
      out, calls = run_free(dir, fstat: listening, survive: "TERM KILL")

      assert_equal "exit=1\n", out
      assert_match(/logger -t brgen CRITICAL: :#{PORT} still held/, calls)
    end
  end
end
