# frozen_string_literal: true

require "minitest/autorun"

class SourceLoopGuardsSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(rel)
    File.read(File.join(ROOT, rel))
  end

  def test_heartbeat_source_requires_explicit_env
    source = read("lib/fix/heartbeat.rb")
    assert_includes source, 'return unless ENV["MASTER_HEARTBEAT"] == "1"'
  end

  def test_watcher_source_requires_explicit_env
    source = read("lib/fix/watcher.rb")
    assert_includes source, 'return unless ENV["MASTER_WATCHER"] == "1"'
  end

  def test_watch_loop_source_requires_explicit_env
    source = read("lib/fix/watch_loop.rb")
    assert_includes source, 'return unless ENV["MASTER_WATCH"] == "1"'
  end
end
