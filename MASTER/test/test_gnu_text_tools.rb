# frozen_string_literal: true

require "test_helper"
require_relative "../law/definition"

# Master::Io::GnuTextTools is the one judge of data/laws.yml zsh.banned_commands:
# the harness hook, MASTER's own shell and the ZSH_NATIVE_PATTERNS Law ask it,
# so a line one of them refuses the others refuse too.
class GnuTextToolsTest < Minitest::Test
  def tools = Master::Io::GnuTextTools.new(Master.law("zsh"))

  def test_the_list_and_every_replacement_come_from_the_law
    section = Master.law("zsh")

    assert_equal section.fetch("banned_commands").map(&:to_s), tools.banned
    tools.banned.each { |name| refute_empty tools.replacement(name), name }
  end

  def test_a_banned_command_without_a_replacement_does_not_load
    section = { "banned_commands" => %w[sed awk], "forbidden_commands" => [{ "command" => "sed", "replacement" => "x" }] }

    error = assert_raises(ArgumentError) { Master::Io::GnuTextTools.new(section) }
    assert_match(/no replacement for awk/, error.message)
  end

  def test_bash_is_banned_as_the_law_says
    assert_equal %w[bash], tools.banned_in("bash -c 'print hi'")
  end

  # Io::Shell published zsh:banned_tool_warning and ran the command anyway.
  def test_masters_own_shell_refuses_what_the_law_bans
    shell = Master::Io::Shell.allocate
    refusal = shell.send(:banned_tool_error, "ls | tail -3")

    assert refusal.err?
    assert_match(/tail: .*Read tool/, refusal.message)
    assert_nil shell.send(:banned_tool_error, %(git commit -m "drop the tail call"))
  end

  def test_the_law_reports_each_line_of_a_zsh_script_and_spares_sh
    ::Law.load_all(File.expand_path("../law", __dir__)) if ::Law.definitions.empty?
    law = ::Law.definitions.fetch(:ZSH_NATIVE_PATTERNS)
    script = "#!/usr/bin/env zsh\nset -euo pipefail\nls | tail -2\ncat <<EOF\nsed in a heredoc\nEOF\nprint ok # sed\n"

    hits = law.scan(script, file: "bin/x.zsh")
    assert_equal [3], hits.map(&:line)
    assert_match(/ZSH_NATIVE_PATTERNS: tail/, hits.first.message)
    assert_empty law.scan("#!/bin/sh\nls | tail -2\n", file: "etc/rc.d/x")
  end
end
