# frozen_string_literal: true
#
# Loads the whole engine as a library. dilla.rb guards its CLI dispatch with
# `if __FILE__ == $PROGRAM_NAME`, so requiring it defines every constant and
# method and runs no command -- which is the same property STUDIO/gate.rb's
# load probe depends on, tested directly in test_engine_sources.rb.

require_relative "../helper"

# Silence the boot chatter; the engine writes a dmesg banner on load.
DILLA_BOOT_ENV = {
  "DILLA_QUIET" => "1",
  "DILLA_ASSET_CHECK" => "0",
  "DILLA_KNOB_CHECK" => "0",
}.freeze
DILLA_BOOT_ENV.each { |key, value| ENV[key] ||= value }

# Loading the engine rewrites tracked files.
#
# Not rendering — loading. `require`ing dilla.rb rewrites project/session.json
# (it rerolls `track` and truncates the section map), learnings/learned_engine
# .json and learnings/playlist_catalog.json, all three of which are committed.
# So running this suite dirtied the working tree every time, which in a repo
# where several agents share one checkout is how engine state ends up swept into
# somebody else's `git commit -a`.
#
# The engine writing session state at load is dilla's business and not a test's
# to change: those files are the running record of a production tool, and
# rewriting when they are written would change what the next render sounds like.
# What a test does owe is to put back exactly what it found.
#
# Byte-for-byte, from memory rather than from git, so this holds in an export
# with no repository and does not depend on what was committed.
DILLA_MUTABLE_STATE = Dir[File.join(Studio::ROOT, "dilla", "project", "**", "*.json")].sort.freeze

DILLA_STATE_BEFORE = DILLA_MUTABLE_STATE.to_h do |path|
  [path, (File.binread(path) if File.file?(path))]
end.freeze

at_exit do
  DILLA_STATE_BEFORE.each do |path, contents|
    next if contents.nil?
    next if File.file?(path) && File.binread(path) == contents

    File.binwrite(path, contents)
  end
end

require_relative "../../dilla/dilla"
