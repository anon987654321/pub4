# frozen_string_literal: true
#
# Loads the whole engine as a library. dilla.rb guards its CLI dispatch with
# `if __FILE__ == $PROGRAM_NAME`, so requiring it defines every constant and
# method and runs no command -- which is the same property STUDIO/gate.rb's
# load probe depends on, tested directly in test_engine_sources.rb.

require_relative "studio_helper"
require "tmpdir"

# Silence the boot chatter; the engine writes a dmesg banner on load. Scratch
# goes to the system temp directory, so a test run leaves nothing under the tree.
DILLA_BOOT_ENV = {
  "DILLA_SCRATCH_DIR" => File.join(Dir.tmpdir, "dilla-test-scratch-#{Process.uid}"),
  "DILLA_QUIET" => "1",
  "DILLA_ASSET_CHECK" => "0",
  "DILLA_KNOB_CHECK" => "0",
}.freeze
DILLA_BOOT_ENV.each { |key, value| ENV[key] ||= value }

require_relative "../dilla/dilla"
