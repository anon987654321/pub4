# frozen_string_literal: true
#
# Loads the whole engine as a library. dilla.rb guards its CLI dispatch with
# `if __FILE__ == $PROGRAM_NAME`, so requiring it defines every constant and
# method and runs no command -- which is the same property STUDIO/gate.rb's
# load probe depends on, tested directly in test_engine_sources.rb.

require_relative "studio_helper"

# Silence the boot chatter; the engine writes a dmesg banner on load.
DILLA_BOOT_ENV = {
  "DILLA_QUIET" => "1",
  "DILLA_ASSET_CHECK" => "0",
  "DILLA_KNOB_CHECK" => "0",
}.freeze
DILLA_BOOT_ENV.each { |key, value| ENV[key] ||= value }

require_relative "../dilla/dilla"
