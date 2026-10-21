# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/capability_graph"

class TestCapabilityGraph < Minitest::Test
  def test_executable_state_uses_real_executables_from_path
    Dir.mktmpdir("capability-path") do |dir|
      executable = File.join(dir, "afplay")
      plain_file = File.join(dir, "pactl")
      directory = File.join(dir, "termux-media-player")
      File.write(executable, "#!/bin/sh\n")
      File.chmod(0o755, executable)
      File.write(plain_file, "not executable")
      Dir.mkdir(directory)

      graph = Operator::CapabilityGraph.new(root: dir, path: File.join(dir, "capabilities.json"))
      previous_path = ENV["PATH"]
      begin
        ENV["PATH"] = dir
        assert_equal "available", graph.send(:executable_state, %w[afplay])
        assert_equal "unavailable", graph.send(:executable_state, %w[pactl])
        assert_equal "unavailable", graph.send(:executable_state, %w[termux-media-player])
      ensure
        previous_path.nil? ? ENV.delete("PATH") : ENV["PATH"] = previous_path
      end
    end
  end
end
