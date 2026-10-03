# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

class TestUndo < Minitest::Test
  Session = Struct.new(:snapshots) do
    def snapshot(path, content)
      snapshots << [path, content]
    end
  end

  def test_undo_restores_the_previous_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      undo = Master::Trace::Undo.new(session: Session.new([]), root: dir)

      assert undo.snapshot(path).ok?
      File.write(path, "after")

      result = undo.undo!

      assert result.ok?
      assert_equal "before", File.read(path)
    end
  end

  def test_undo_removes_a_file_that_did_not_exist_before_the_write
    Dir.mktmpdir do |dir|
      path = File.join(dir, "new.txt")
      undo = Master::Trace::Undo.new(session: Session.new([]), root: dir)

      assert undo.snapshot(path).ok?
      File.write(path, "created")

      result = undo.undo!

      assert result.ok?
      refute File.exist?(path)
    end
  end
end
