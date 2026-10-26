#!/usr/bin/env ruby
# frozen_string_literal: true

# PreToolUse hook for Edit and Write. An agent's hand edit meets the same mechanical
# laws as an edit /fix makes: the file as it would be left is judged by
# Fix::WriteGuard, and a finding the edit introduces at veto, critical or error
# severity refuses it. Constitutional configuration is validated like other source.

# Why here: /fix and the design loop were held to the guard, and a hand edit or an
# applied patch was not, so the laws bound the machine and not the agent beside it.

# Reads the hook JSON on stdin. Exit 2 with the reason on stderr blocks the call.
# Anything it cannot judge is let through (a payload it cannot parse, a file outside
# the checkout, a binary or large file, a guard that raises): this guard must never
# be the reason an edit tool stops working.

require "json"

MAX_BYTES = 400_000
CHECKED = /\.(?:rb|rake|ru|scss|css|js|mjs|yml|yaml|erb|html|md|sh|zsh)\z/

def checkout_root(path)
  dir = File.dirname(File.expand_path(path))
  dir = File.dirname(dir) until Dir.exist?(dir) || dir == "/"
  until dir == "/"
    return dir if File.file?(File.join(dir, "MASTER", "data", "laws.yml"))

    dir = File.dirname(dir)
  end
  nil
end

# The content the tool would leave in the file; nil when the edit cannot be reproduced.
def resulting_content(tool:, input:, path:)
  return input["content"].to_s if tool == "Write"

  old = input["old_string"].to_s
  return if old.empty? || !File.file?(path)

  text = File.read(path, encoding: "UTF-8")
  return unless text.include?(old)

  input["replace_all"] ? text.gsub(old) { input["new_string"].to_s } : text.sub(old) { input["new_string"].to_s }
end

payload = begin
  JSON.parse($stdin.read)
rescue JSON::ParserError
  exit 0
end

tool = payload["tool_name"].to_s
input = payload["tool_input"] || {}
path = input["file_path"].to_s
exit 0 unless %w[Edit Write].include?(tool) && !path.empty?

path = File.expand_path(path)
root = checkout_root(path)
exit 0 unless root

exit 0 unless path.match?(CHECKED)

content = resulting_content(tool:, input:, path:)
exit 0 if content.nil? || content.bytesize > MAX_BYTES

begin
  $LOAD_PATH.unshift(File.join(root, "MASTER", "lib"))
  require "master"
  require "fix/write_guard"
  verdict = Master::Fix::WriteGuard.default.verdict(path:, content:)
  exit 0 unless verdict.blocked?

  warn "law-check: this #{tool.downcase} introduces a finding the laws refuse in #{path.delete_prefix("#{root}/")}:"
  warn "  #{verdict.reason}"
  warn "  Fix the cause (MASTER/bin/operator laws <ID> names the exemption), then retry."
  exit 2
rescue SystemExit
  raise
rescue StandardError, LoadError
  exit 0
end
