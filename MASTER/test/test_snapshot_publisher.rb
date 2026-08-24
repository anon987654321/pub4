# frozen_string_literal: true

require_relative "test_helper"

class TestSnapshotPublisher < Minitest::Test
  def test_write_digest_and_archive
    Dir.mktmpdir do |target|
      File.write(File.join(target, "sample.rb"), "puts 42\n")
      Dir.mktmpdir do |downloads|
        prior = ENV["MASTER_SNAPSHOT_DIR"]
        ENV["MASTER_SNAPSHOT_DIR"] = downloads
        pub = Master::Trace::Snapshot::Publisher
        messages = pub.write(target:, label: "TEST", mode: :both)

        assert_equal 2, messages.size
        digest = File.join(downloads, "TEST_snapshot.md")
        archive = Dir.glob(File.join(downloads, "TEST_snapshot_*.md")).first
        assert File.file?(digest)
        assert File.file?(archive)
        body = File.read(digest)
        assert_includes body, "## Agent analysis protocol"
        assert_includes body, "puts 42"
      ensure
        prior ? ENV["MASTER_SNAPSHOT_DIR"] = prior : ENV.delete("MASTER_SNAPSHOT_DIR")
      end
    end
  end

  def test_artifacts_section_reads_downloads_not_repo_root
    Dir.mktmpdir do |downloads|
      prior = ENV["MASTER_SNAPSHOT_DIR"]
      ENV["MASTER_SNAPSHOT_DIR"] = downloads
      File.write(File.join(downloads, "MASTER_snapshot.md"), "# digest\n")
      section = Master::Trace::Snapshot::Publisher.artifacts_section
      assert section.any? { |line| line.include?(downloads) }
      refute section.any? { |line| line.include?("repo root") }
    ensure
      prior ? ENV["MASTER_SNAPSHOT_DIR"] = prior : ENV.delete("MASTER_SNAPSHOT_DIR")
    end
  end
end
