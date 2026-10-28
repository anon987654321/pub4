#!/usr/bin/env ruby
# frozen_string_literal: true

# The boot the operator's machine ran, in the order it ran it: master.rb's
# zeitwerk setup, the builder chain into fix/kernel.rb, then the three legacy
# aliases. Every managed constant starts as a pending autoload, and an alias
# head that const_sets into one crashes in the builder chain — the phase this
# check runs first, because it needs only Ruby and zeitwerk. The alias
# identity is asserted strictly wherever the fix graph's gems are installed
# (boot_smoke's env) and reported unverified rather than failed where they
# are not: a missing gem is an environment, a NameError is the 2026-10-28
# crash class (346da8e), and only one of those may pass quietly.

require "rbconfig"

root = File.expand_path("..", __dir__)
lib = File.join(root, "lib")

begin
  require "zeitwerk"
rescue LoadError
  warn "kernel_autoload_smoke: zeitwerk is not available — the boot phase " \
       "needs only it and stdlib; install the gem or point RUBYLIB at a checkout"
  exit 1
end

$LOAD_PATH.unshift(lib)
begin
  require "master" # the real boot entry: Master module + zeitwerk setup
rescue StandardError, ScriptError => e
  warn "kernel_autoload_smoke: master.rb failed to load: #{e.class}: #{e.message}"
  warn e.backtrace.first(8).join("\n")
  exit 1
end

pending_kernel = Master::Fix.autoload?(:Kernel)
unless pending_kernel
  warn "kernel_autoload_smoke: Master::Fix::Kernel is not a pending autoload — " \
       "the loader setup this check guards has changed; update the check with it"
  exit 1
end

begin
  # The real boot path: bootstrap_container references Builder (pending
  # autoload), which require_relative-chains into fix/kernel.rb, whose
  # lifecycle file opens Kernel and installs the canonical adapter classes.
  require "builder"
rescue NameError => e
  warn "kernel_autoload_smoke: the 2026-10-28 crash class, in the builder chain: #{e.message}"
  warn e.backtrace.first(8).join("\n")
  exit 1
rescue StandardError, ScriptError => e
  warn "kernel_autoload_smoke: the builder chain crashed: #{e.class}: #{e.message}"
  warn e.backtrace.first(8).join("\n")
  exit 1
end

# The lazy fix graphs, triggered through the legacy aliases exactly the way
# runtime callers (build_fix_loop / build_repair_loop) and old references to
# RunJournal reach them. Each reference fires a pending zeitwerk autoload; an
# unguarded alias head crashes here, and a gem-less executor stops here with
# an honest partial verdict instead of a false pass.
verified = []
unverified = []
{ "FixLoop" => "ConvergenceAdapter",
  "RepairLoop" => "RepairAdapter",
  "RunJournal" => "LifecycleJournal" }.each do |legacy, adapter|
  begin
    actual = Master::Fix.const_get(legacy) # rubocop:disable Style/RedundantConstantGet -- fires the pending autoload on purpose
    canonical = Master::Fix::Kernel.const_get(adapter)
    unless actual.equal?(canonical)
      warn "kernel_autoload_smoke: #{legacy} is #{actual}, not the Kernel-owned #{adapter}"
      exit 1
    end
    verified << legacy
  rescue LoadError => e
    missing = e.message.split("-- ").last.to_s.strip
    unverified << "#{legacy} (needs #{missing})"
  rescue NameError => e
    warn "kernel_autoload_smoke: the 2026-10-28 crash class, at alias #{legacy}: #{e.message}"
    warn e.backtrace.first(8).join("\n")
    exit 1
  end
end

verdict = "kernel_autoload_smoke: boot chain clean under zeitwerk"
verdict += "; alias identity verified for #{verified.join(', ')}" if verified.any?
verdict += "; identity unverified without the bundle for #{unverified.join(', ')}" if unverified.any?
puts verdict
exit 1 if verified.empty? && unverified.any? # nothing measured is not a pass
