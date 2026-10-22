#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Code may not call a turn finished while a file it changed this session breaks a law on a line it
# changed. It is MASTER's evidence-gated finish applied to the agent beside it: Core::Proof refuses `done`
# without evidence, and this refuses a finish without a clean `bin/operator lint`.

# One script, both events, as require_law_first.rb does. `finish_check.rb record` (PostToolUse on Edit and
# Write) remembers which files the session changed; with no argument (Stop) it judges exactly those, so
# another session's half-finished work in a shared checkout never blocks this one. Only the lines this
# diff added are judged (--changed-lines), the shape a finish wants: a file's standing debt does not hold
# a turn hostage. A file git does not track yet is judged whole, since every line of it is this session's.

# Reads the hook JSON on stdin. Exit 2 with the findings on stderr sends them back to the agent. Anything
# it cannot judge passes, and a second stop in a row always passes (stop_hook_active), so this guard can
# never be the reason a session cannot end. PUB4_FINISH_CHECK_OPERATOR names another operator, which is how
# the tests stand a stub in for a lint that boots the whole runtime.

require "json"
require "open3"
require "tmpdir"

LINTABLE = /\.(?:rb|rake|ru|scss|css|js|mjs|yml|yaml|erb|html|sh|zsh)\z/
MAX_FILES = 40
MAX_FINDINGS = 25

def edits_file(session) = File.join(Dir.tmpdir, "pub4-edits-#{session.to_s.gsub(/\W/, "_")}")

def checkout_root(path)
  dir = File.dirname(path)
  dir = File.dirname(dir) until Dir.exist?(dir) || dir == "/"
  until dir == "/"
    return dir if File.file?(File.join(dir, "MASTER", "data", "laws.yml"))

    dir = File.dirname(dir)
  end
  nil
end

def record(payload)
  response = payload["tool_response"]
  path = (response.is_a?(Hash) && response["filePath"]) || payload.dig("tool_input", "file_path")
  return unless %w[Edit Write].include?(payload["tool_name"].to_s) && path.to_s != ""

  File.open(edits_file(payload["session_id"]), "a") { |file| file.puts(File.expand_path(path)) }
end

def lint(root, args)
  operator = ENV.fetch("PUB4_FINISH_CHECK_OPERATOR", File.join(root, "MASTER", "bin", "operator"))
  out, status = Open3.capture2e(operator, "lint", *args)
  return [] if status.success? || status.exitstatus.nil? || out.empty?

  out.lines.grep(/\Alint0: /).reject { |line| line.include?("clean,") || line.include?(" finding(s) across ") }
end

def tracked?(root, path)
  system("git", "-C", root, "ls-files", "--error-unmatch", path, out: File::NULL, err: File::NULL)
end

def findings_for(root, files)
  tracked, fresh = files.partition { |path| tracked?(root, path) }
  found = []
  found += lint(root, ["--changed-lines", *tracked]) unless tracked.empty?
  found += lint(root, fresh) unless fresh.empty?
  found.first(MAX_FINDINGS)
end

# The session's edited files that sit in a pub4 checkout, as [root, files]; nil when there is nothing to judge.
def edited_files(payload)
  list = edits_file(payload["session_id"])
  return unless File.file?(list)

  files = File.readlines(list, chomp: true).uniq.select { |path| File.file?(path) && path.match?(LINTABLE) }
  root = files.first && checkout_root(files.first)
  return unless root

  [root, files.select { |path| path.start_with?("#{root}/") }.first(MAX_FILES)]
end

def finish(payload)
  root, files = edited_files(payload)
  found = root ? findings_for(root, files) : []
  return if found.empty?

  warn "finish-check: a file you changed breaks a law on a line you changed. Fix these, then finish:"
  found.each { |line| warn "  #{line.sub("lint0: ", "").strip}" }
  warn "  (MASTER/bin/operator laws <ID> names the law and what it spares.)"
  exit 2
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError => e
  warn "finish-check: unreadable hook payload (#{e.class}); letting it through"
  exit 0
end

if ARGV.first == "record"
  record(payload)
elsif !payload["stop_hook_active"]
  finish(payload)
end
exit 0
