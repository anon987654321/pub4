# frozen_string_literal: true

require_relative "test_helper"

class TestSessionRecovery < Minitest::Test
  def test_corrupt_session_is_quarantined_and_startup_continues
    Dir.mktmpdir do |dir|
      master_dir = File.join(dir, ".master")
      FileUtils.mkdir_p(master_dir)
      path = File.join(master_dir, "session.json")
      File.write(path, "{ definitely not json")

      session = Master::Trace::Session.new(root: dir)
      assert_same session, session.load!
      refute File.exist?(path)
      assert_operator Dir.glob("#{path}.corrupt.*").length, :>=, 1
    end
  end
end
