#!/usr/bin/env ruby
# frozen_string_literal: true

# Dilla's executable boundary. The music engine and live vocabulary live in
# lib/; the frozen liveset and Röyksopp pad player remain separate programs.

require "rbconfig"

ROOT = File.expand_path(__dir__)
LIVESET = File.join(ROOT, "liveset.rb")
ROYKSOPP = File.join(ROOT, "royksopp.rb")

def run_script(path, *args)
  abort "dilla: missing #{path}" unless File.file?(path)

  exec(RbConfig.ruby, path, *args)
end

command, *args = ARGV

case command
when "live"
  mode, *rest = args

  case mode
  when nil, "default", "liveset", "set"
    run_script(LIVESET, *rest)
  when "royksopp", "royksopp_live", "melody_a.m.", "melody_am"
    run_script(ROYKSOPP, *rest)
  when "status"
    require_relative "lib/livesets"
    puts Livesets::Session.status
  when "stop"
    require_relative "lib/livesets"
    puts Livesets::Session.stop!
  else
    require_relative "lib/livesets"
    LiveSynth.main([mode, *rest])
  end
when "royksopp", "royksopp.rb"
  run_script(ROYKSOPP, *args)
when "liveset", "liveset.rb"
  run_script(LIVESET, *args)
else
  abort <<~USAGE
    dilla: live audio entrypoint
    usage: ruby dilla.rb live [default|royksopp|status|stop|improvise|progression|patch|knob|morph|say]
           ruby dilla.rb royksopp
           ruby dilla.rb liveset
  USAGE
end
