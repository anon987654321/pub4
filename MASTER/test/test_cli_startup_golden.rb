# frozen_string_literal: true

require_relative "test_helper"
require "pty"
require "io/console"
require "tmpdir"

# Boots the real bin/master in a pseudo-terminal and holds its first lines to the shape an OpenBSD dmesg
# has. Slow (a boot takes tens of seconds), so it runs only with MASTER_PTY_TESTS=1.
class TestCliStartupGolden < Minitest::Test
  BOOT_WAIT_S = 120
  ANSI = /\e\[[0-9;?]*[A-Za-z]|\e[()][A-Z0-9]/

  SHAPE = [
    /\Amaster0 at mainbus0: MASTER \d+\.\d+\.\d+ #\d+, model \S+\z/,
    /\Ahost0 at mainbus0: \S+@\S+:\/\S+\z/,
    /\Avoice0 at mainbus0: (?:ready|degraded)\z/,
    /\Aweb0 at mainbus0: /,
    /\Anet0 at mainbus0: wifi \w+, power (?:on|off), (?:link up|no link)\z/,
    /\Abth0 at mainbus0: (?:on|off), \d+ connected\z/,
    /\Aroot on master0\z/,
  ].freeze

  def test_timeout = BOOT_WAIT_S + 15

  def test_the_first_lines_have_the_dmesg_shape_in_order
    skip "set MASTER_PTY_TESTS=1 to boot bin/master in a terminal" unless ENV["MASTER_PTY_TESTS"] == "1"

    attach = boot_lines.grep(/\A(?:master0|host0|voice0|web0|net0|bth0|root on) /)
    ranks = attach.map { |line| rank(line) }

    assert_operator attach.size, :>=, 5, attach.join("\n")
    refute_includes ranks, SHAPE.size, "off shape: #{attach.reject { |line| rank(line) < SHAPE.size }.inspect}"
    assert_equal ranks.sort, ranks, "out of order"
  end

  def test_the_shape_accepts_the_lines_a_real_boot_prints
    sample = ["master0 at mainbus0: MASTER 1.0.3 #22497, model claude-sonnet-5-5",
              "host0 at mainbus0: mac@Mac.localdomain:/Users/mac/pub4/MASTER",
              "voice0 at mainbus0: ready", "web0 at mainbus0: ready, token set",
              "net0 at mainbus0: wifi en0, power on, link up", "bth0 at mainbus0: on, 1 connected", "root on master0"]

    assert(sample.all? { |line| SHAPE.any? { |shape| line.match?(shape) } })
  end

  private

  def rank(line) = SHAPE.index { |shape| line.match?(shape) } || SHAPE.size

  def clean_command
    ["env", "-i", "HOME=#{Dir.home}", "PATH=#{ENV["PATH"]}", "USER=#{ENV.fetch("USER", "dev")}",
     "TERM=xterm-256color", "MASTER_INTERNAL_CHILD=1", "MASTER_BOOT_SOUND=0", "MASTER_FACE_ON_START=0",
     File.join(Master::ROOT, "bin", "master")]
  end

  def boot_lines
    out = +""
    PTY.spawn(*clean_command) do |reader, _writer, pid|
      reader.winsize = [40, 120]

      thread = Thread.new { loop { out << reader.readpartial(65_536) } rescue nil }
      wait_for_root(out)
      Process.kill("TERM", pid)
      thread.kill
    end
    plain_lines(out)
  end

  def plain_lines(out)
    text = out.dup.force_encoding("UTF-8").scrub.gsub(ANSI, "")
    text.lines.filter_map { |line| (stripped = line.strip).empty? ? nil : stripped }
  end

  def wait_for_root(out)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BOOT_WAIT_S
    sleep 1 until out.include?("root on master0") || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end
end
