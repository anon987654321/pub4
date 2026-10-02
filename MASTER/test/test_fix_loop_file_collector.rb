# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

# /scan and /fix used to keep separate exclusion lists, and the fix side's was a
# strict subset. Scanner::SKIP_RELATIVE_PATHS names the generated and vendored
# web bundles, so /scan left them alone while `/fix .` proposed thousands of
# edits against a minified THREE build and against a file whose first line says
# "do not edit by hand". These pin the single list and the reporting that keeps
# the narrowing visible.
class TestFixLoopFileCollector < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize = @events = []
    def publish(event, payload = {}) = @events << [event, payload]
  end

  def collector(root, bus: nil) = Master::Fix::FixLoop::FileCollector.new(root:, bus:)

  def write(root, rel, body = "x = 1\n")
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  def test_generated_and_vendored_paths_are_not_collected_for_fixing
    Dir.mktmpdir do |dir|
      authored = write(dir, "lib/thing.rb")
      write(dir, "web/public/face.runtime.js", "const a = 1;\n")
      write(dir, "web/public/three.face.module.js", "var b = 2;\n")
      write(dir, "web/public/face_vision.bundle.js", "const c = 3;\n")
      write(dir, "reports/run.yml", "a: 1\n")
      write(dir, "vendor/gem/lib/dep.rb")

      collected = collector(dir).collect(dir)

      assert_includes collected, authored
      assert_equal [authored], collected
    end
  end

  def test_skipped_files_are_counted_and_published
    Dir.mktmpdir do |dir|
      bus = FakeBus.new
      write(dir, "lib/thing.rb")
      write(dir, "web/public/face.runtime.js", "const a = 1;\n")

      collected = collector(dir, bus:).collect(dir)

      assert_equal 1, collected.size
      assert_equal 1, collector(dir, bus:).collect(dir).size
      skipped = bus.events.select { |name, _| name == "fix_loop:skipped" }
      refute_empty skipped, "narrowing the fix input must be announced"
      assert_equal 1, skipped.first.last[:count]
      assert_includes skipped.first.last[:sample], "web/public/face.runtime.js"
    end
  end

  def test_collector_and_scanner_agree_on_what_is_off_limits
    Dir.mktmpdir do |dir|
      %w[
        web/public/three.face.module.js
        web/public/face.runtime.js
        reports/run.yml
        vendor/gem/lib/dep.rb
        knowledge/note.md
        RAILS/brgen/app/views/pwa/service-worker.js
      ].each do |rel|
        path = write(dir, rel, "x\n")

        assert Master::Review::Scan::Scanner.skip_path?(path, root: dir), "scanner skips #{rel}"
        assert collector(dir).__send__(:skipped?, path), "fix collector skips #{rel}"
      end
    end
  end

  def test_authored_source_is_off_limits_to_neither
    Dir.mktmpdir do |dir|
      path = write(dir, "lib/review/thing.rb")

      refute Master::Review::Scan::Scanner.skip_path?(path, root: dir)
      refute collector(dir).__send__(:skipped?, path)
    end
  end

  # soul.yml owns sacred paths; rules.yml is the law catalogue. /fix must never
  # collect the constitutional data or core spine for repair.
  def test_sacred_paths_are_never_collected
    files = collector(Master::ROOT).collect(Master::ROOT).map { |f| f.delete_prefix("#{Master::ROOT}/") }

    refute_includes files, "data/rules.yml"
    refute_includes files, "data/soul.yml"
    refute(files.any? { |f| f.start_with?("lib/core/") })
    assert_includes files, "lib/fix/fix_loop.rb"
  end

  def test_repository_root_git_paths_are_resolved_for_master_and_rails_targets
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "MASTER/lib"))
      FileUtils.mkdir_p(File.join(dir, "RAILS/brgen/app"))
      write(dir, "MASTER/lib/thing.rb")
      write(dir, "RAILS/brgen/app/models/post.rb")
      system("git", "-C", dir, "init", "-q", "--initial-branch=main")
      system("git", "-C", dir, "config", "user.email", "test@example.invalid")
      system("git", "-C", dir, "config", "user.name", "Test")
      system("git", "-C", dir, "add", "-A")
      system("git", "-C", dir, "commit", "-qm", "initial")

      master_target = File.join(dir, "MASTER")
      rails_target = File.join(dir, "RAILS")
      assert_equal [File.join(dir, "MASTER/lib/thing.rb")], collector(dir).collect(master_target)
      assert_equal [File.join(dir, "RAILS/brgen/app/models/post.rb")], collector(dir).collect(rails_target)
    end
  end

  def test_incremental_collection_includes_untracked_files_and_respects_target
    Dir.mktmpdir do |dir|
      write(dir, "MASTER/lib/tracked.rb")
      write(dir, "RAILS/brgen/app/models/post.rb")
      system("git", "-C", dir, "init", "-q", "--initial-branch=main")
      system("git", "-C", dir, "config", "user.email", "test@example.invalid")
      system("git", "-C", dir, "config", "user.name", "Test")
      system("git", "-C", dir, "add", "-A")
      system("git", "-C", dir, "commit", "-qm", "initial")
      write(dir, "RAILS/brgen/app/models/untracked.rb")
      write(dir, "MASTER/lib/changed.rb")

      changed = collector(dir).collect_changed(File.join(dir, "RAILS"))

      assert_equal [File.join(dir, "RAILS/brgen/app/models/untracked.rb")], changed
    end
  end
end
