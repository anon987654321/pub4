#!/usr/bin/env ruby
# frozen_string_literal: true

# Dilla's executable boundary. Music lives in lib/; the live entrypoints are
# kept as separate programs so they can be run, stopped and inspected without
# booting the full render engine.

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
  when "say"
    require_relative "lib/livesets"
    puts Livesets::Say.call(rest.join(" "))
  else
    # LiveSynth commands are owned by livesets.rb; forward them through its
    # command vocabulary rather than duplicating patch/knob parsing here.
    require_relative "lib/livesets"
    puts Livesets::Say.call([mode, *rest].join(" "))
  end
when "royksopp", "royksopp.rb"
  run_script(ROYKSOPP, *args)
when "liveset", "liveset.rb"
  run_script(LIVESET, *args)
else
  abort <<~USAGE
    dilla: live audio entrypoint
    usage: ruby dilla.rb live [default|royksopp|status|stop|say TEXT]
           ruby dilla.rb royksopp
           ruby dilla.rb liveset
  USAGE
end
