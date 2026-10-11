#!/usr/bin/env ruby
# frozen_string_literal: true

# Boots the container far enough to construct the FixLoop, the way
# `bin/master "/fix ..."` does, and stops there: no fix, no model call, no
# background thread. A reader of a removed method (Laws#thresholds once
# crashed FixLoop#initialize) passes every unit test that stubs the loop and
# fails only at boot; this is the check that boots it.

require "tmpdir"

ENV["MASTER_LOCAL_ONLY"] = "1"
ENV["MASTER_SKIP_TTS"] = "1"
ENV["MASTER_SKIP_BOOT_SCAN"] = "1"
ENV["MASTER_WEB"] = "0"
ENV["MASTER_WATCHER"] = "0"
ENV["MASTER_INTERNAL_CHILD"] = "1"
%w[MASTER_AUTOFIX MASTER_WATCH MASTER_FULL_BOOT MASTER_STRICT_BOOT].each { |key| ENV.delete(key) }

root = File.expand_path("..", __dir__)
require_relative "../lib/boot/entrypoint"
Master::Boot::Entrypoint.prepare!(root:)
$LOAD_PATH.unshift(File.join(root, "lib"))
Dir.chdir(root)
require "master"
require "ops"

begin
  infra = Master::Builder.build_infrastructure(root)
  ai = Master::Builder.build_ai(root, infra)
  loop_class = ai[:fix_loop].class
  unless loop_class == Master::Fix::FixLoop
    warn "boot_smoke: expected a FixLoop, built #{loop_class}"
    exit 1
  end
  # initialize ran; now read every convergence knob it exposes.
  fix_loop = ai[:fix_loop]
  [fix_loop.max_passes_default, fix_loop.clean_runs_required, fix_loop.plateau_window].each do |value|
    raise "convergence config returned #{value.inspect}" unless value.is_a?(Integer)
  end
  puts "boot_smoke: FixLoop built, max_passes=#{fix_loop.max_passes_default} " \
       "clean_runs=#{fix_loop.clean_runs_required} plateau_window=#{fix_loop.plateau_window}"
rescue StandardError, ScriptError => e
  warn "boot_smoke: #{e.class}: #{e.message}"
  warn e.backtrace.first(8).join("\n")
  exit 1
end
# Background indexers started by the build would hold the process open.
$stdout.flush
$stderr.flush
exit!(0)
