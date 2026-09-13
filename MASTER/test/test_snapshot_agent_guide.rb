# frozen_string_literal: true

require_relative "test_helper"

class TestSnapshotAgentGuide < Minitest::Test
  def test_render_includes_analysis_protocol_sections
    body = Master::Trace::Snapshot::AgentGuide.render(label: "OPENBSD")

    assert_includes body, "## Agent analysis protocol"
    assert_includes body, "Word-for-word read + cross-reference"
    assert_includes body, "Deep execution traces"
    assert_includes body, "Rehydrate files locally"
    assert_includes body, "OPERATOR_snapshot.md"
  end

  def test_snapshot_digest_includes_agent_protocol
    Dir.mktmpdir do |target|
      File.write(File.join(target, "sample.rb"), "puts 42\n")
      Dir.mktmpdir do |downloads|
        prior = ENV["MASTER_SNAPSHOT_DIR"]
        ENV["MASTER_SNAPSHOT_DIR"] = downloads
        Master::Trace::Snapshot::Publisher.write(target:, label: "TEST", repo_root: File.expand_path("..", target), mode: :digest)
        body = File.read(File.join(downloads, "TEST_snapshot.md"))

        assert_includes body, "## Agent analysis protocol"
        assert_includes body, "## Tree"
        assert body.index("## Agent analysis protocol") < body.index("## Tree")
      ensure
        prior ? ENV["MASTER_SNAPSHOT_DIR"] = prior : ENV.delete("MASTER_SNAPSHOT_DIR")
      end
    end
  end
end
