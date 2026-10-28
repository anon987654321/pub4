# frozen_string_literal: true

require_relative "../test_helper"

class TestVoiceBedRemoved < Minitest::Test
  RUNTIME_PATHS = %w[
    lib/voice/narrator.rb
    lib/cli/session.rb
    lib/cli/session/repl_flow.rb
    lib/cli/command_registry.rb
    lib/cli/face/window.rb
  ].freeze

  def test_bard_has_no_background_bed_configuration
    refute Master::Voice::Narrator.load_config(:bard).key?("bed")
  end

  def test_runtime_has_no_dilla_bed_start_stop_or_microphone_gating
    RUNTIME_PATHS.each do |relative|
      source = File.read(File.join(Master::ROOT, relative))
      refute_match(/(?:Master::Voice::)?Bed\.(?:start|boot|stop|release|foreground\?)/, source, relative)
    end
  end
end
