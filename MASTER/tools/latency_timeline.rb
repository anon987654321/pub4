#!/usr/bin/env ruby
# frozen_string_literal: true

# One monotonic timeline of an interactive MASTER turn, measured in a real
# terminal: spawn to the first byte, the prompt and the greeting, then a
# message to the first line of reply text and to the reply's last output. It
# boots the CLI as an operator would (not safe mode, not the fast path), with
# the chord bed and speech off, and makes live model calls, so it costs quota.
#
#   ruby tools/latency_timeline.rb ["message"] [--json]

require "json"
require "pty"
require "rbconfig"

ROOT = File.expand_path("..", __dir__)
PROMPT = /\S+:\S+\$ /
ANSI = /\e(?:\[[0-9;?]*[A-Za-z]|[78])/
# Lines MASTER prints about itself rather than as the reply: dmesg units
# ("llm1 at master0: ...", "exec0: 35 bytes"), the state line and the prompt.
UNIT_LINE = /\A[a-z]+\d+(?: at [a-z]+\d+)?: /
# The thinking spinner: a glyph, the stage, the seconds so far.
SPINNER = /\A\S \S+ \d+(?:\.\d+)?s\z/
ENV_FOR_PTY = {
  "MASTER_RUBY_REEXEC_DONE" => "1", "TERM" => "xterm", "MASTER_FACE_ON_START" => "0",
  "MASTER_WEB" => "0", "MASTER_BACKGROUND" => "0", "MASTER_AUTOFIX" => "0",
  "MASTER_WATCH" => "0", "MASTER_WATCHER" => "0", "MASTER_HEARTBEAT" => "0", "MASTER_SKIP_TTS" => "1",
  "MASTER_BED" => "0"
}.freeze
BOOT_LIMIT_S = 120
GREETING_LIMIT_S = 30
REPLY_LIMIT_S = 180
QUIET_S = 3
EXIT_LIMIT_S = 20

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# [seconds since origin, plain text] for each chunk until the block says stop
# or the limit passes.
def collect(reader, origin, limit_s, chunks = [])
  deadline = now + limit_s
  until now > deadline || yield(chunks)
    next unless reader.wait_readable(0.05)

    chunks << [now - origin, reader.readpartial(65_536).gsub(ANSI, "").delete("\r")]
  end
  chunks
rescue Errno::EIO, EOFError
  chunks
end

def reply_line?(line, message)
  text = line.strip
  !text.empty? && !text.match?(UNIT_LINE) && !text.match?(/\S+:\S+\$(?: |\z)/) && !text.include?(message) &&
    !text.match?(SPINNER) &&
    !text.match?(/\A\S+ \S+ \S+ \S+, \S+, [\d.]+k?\/[\d.]+k\z/)
end

# Seconds from ^D to the process being gone, or nil when it outlived the limit
# and was terminated. A child already reaped counts as gone. The terminal is
# read throughout: a BSD process closing its tty waits for its output to drain,
# so an unread terminal holds the exit open and reads as a hang.
def exit_seconds(reader, writer, pid)
  asked = now
  writer.write("\x04")
  loop do
    return now - asked if Process.wait(pid, Process::WNOHANG)
    break if now - asked > EXIT_LIMIT_S

    reader.read_nonblock(65_536, exception: false)
    sleep 0.05
  end
  Process.kill("TERM", pid)
  nil
rescue Errno::ECHILD, Errno::EIO, PTY::ChildExited
  now - asked
end

json = ARGV.delete("--json")
message = ARGV.first || "hi, what time is it in Oslo?"
marks = {}
started = now

PTY.spawn(ENV_FOR_PTY, RbConfig.ruby, File.join(ROOT, "bin", "cli"), chdir: ROOT) do |reader, writer, pid|
  boot = collect(reader, started, BOOT_LIMIT_S) { |chunks| chunks.map(&:last).join.match?(PROMPT) }
  marks[:first_byte] = boot.find { |_, text| !text.empty? }&.first
  marks[:prompt] = boot.last&.first if boot.map(&:last).join.match?(PROMPT)
  greeting = collect(reader, started, GREETING_LIMIT_S) { |chunks| chunks.map(&:last).join.include?("\n") }
  marks[:greeting] = greeting.find { |_, text| text.include?("\n") }&.first
  marks[:greeting_text] = greeting.map(&:last).join.lines.first.to_s.strip

  sent = now
  writer.write("#{message}\n")
  turn = collect(reader, sent, REPLY_LIMIT_S) do |chunks|
    replied = chunks.any? { |_, text| text.lines.any? { |line| reply_line?(line, message) } }
    replied && now - sent - chunks.last.first > QUIET_S
  end
  if ENV["LATENCY_DEBUG"]
    File.write(ENV["LATENCY_DEBUG"], turn.map { |at, text| "#{at.round(2)} #{text.inspect}" }.join("\n"))
  end
  first = turn.find { |_, text| text.lines.any? { |line| reply_line?(line, message) } }
  marks[:first_reply_text] = first&.first
  marks[:reply_complete] = turn.reverse.find { |_, text| !text.strip.empty? && !text.strip.match?(/\A#{PROMPT}\z/) }&.first if first
  marks[:reply_text] = first&.last.to_s.lines.find { |line| reply_line?(line, message) }.to_s.strip

  marks[:exit] = exit_seconds(reader, writer, pid)
rescue Errno::EIO, PTY::ChildExited
  nil
end

seconds = marks.transform_values { |value| value.is_a?(Float) ? value.round(2) : value }
if json
  puts JSON.pretty_generate(seconds.merge(message:))
else
  puts "latency0: boot first byte #{seconds[:first_byte] || "never"}s, prompt #{seconds[:prompt] || "never"}s, " \
       "greeting #{seconds[:greeting] || "never"}s"
  puts "latency0: reply first text #{seconds[:first_reply_text] || "never"}s, " \
       "last output #{seconds[:reply_complete] || "never"}s, ^D exit #{seconds[:exit] ? "#{seconds[:exit]}s" : "hung"}"
  puts "latency0: greeting #{seconds[:greeting_text].inspect}"
  puts "latency0: reply #{seconds[:reply_text].inspect}"
end
