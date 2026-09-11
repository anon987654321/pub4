# frozen_string_literal: true

require "minitest/autorun"

# An rc.d script that sources an env file must export it.
#
# `.` sets a bare KEY=value without exporting it, so `. /etc/brgen.env && export
# RAILS_ENV=production SECRET_KEY_BASE ...` is an allowlist nobody can see: only
# the keys written onto that line reach the process, and a key added to the file
# later does nothing. rc.d/brgen carries the story — VAPID_PUBLIC_KEY sat in
# /etc/brgen.env for hours while push failed silently — and was fixed with
# `set -a && . file && set +a`.
#
# The three job workers were not fixed with it, and they are where it matters
# most: the classes brgen_jobs exists to run include WebPushJob, which wants the
# VAPID pair the app could not see either. Found 2026-09-11, all three at once,
# which is what a fix applied to one file of a family looks like a month later.
#
# Text, not execution: these run as root on OpenBSD and this asserts their shape.
class RcEnvExportTest < Minitest::Test
  RC_D = File.expand_path("../etc/rc.d", __dir__)

  # rails-app.tmpl is the generator for a new app rather than a running service.
  # It is held to the same rule, because a template that teaches the bug writes
  # the bug into every app made from it.
  def scripts
    Dir.glob(File.join(RC_D, "*")).select { |path| File.file?(path) }.sort
  end

  def daemon_flags(source)
    source[/^daemon_flags=.*/]
  end

  def test_every_script_that_sources_an_env_file_in_daemon_flags_exports_it
    offenders = scripts.filter_map do |path|
      flags = daemon_flags(File.read(path))
      next unless flags
      next unless flags.match?(%r{\.\s+/etc/[\w./-]+\.env})
      next if flags.include?("set -a")

      File.basename(path)
    end

    assert_empty offenders,
                 "these source an env file without set -a, so only the keys named after it are exported: #{offenders.join(', ')}"
  end

  # The guard has to be looking at something. If the glob or the daemon_flags
  # match breaks, the test above passes by finding nothing.
  def test_the_guard_reads_a_real_population
    sourcing = scripts.count do |path|
      flags = daemon_flags(File.read(path))
      flags&.match?(%r{\.\s+/etc/[\w./-]+\.env})
    end

    assert_operator sourcing, :>=, 6,
                    "three apps and three job workers source an env file in daemon_flags; a smaller number means the scan broke"
  end

  # set -a without set +a leaves every later assignment in that command line
  # exported too, which is not what the apps do and not what was intended.
  def test_the_export_window_is_closed_again
    unclosed = scripts.filter_map do |path|
      flags = daemon_flags(File.read(path)).to_s
      next unless flags.include?("set -a")
      next if flags.include?("set +a")

      File.basename(path)
    end

    assert_empty unclosed, "set -a is opened and never closed in: #{unclosed.join(', ')}"
  end
end
