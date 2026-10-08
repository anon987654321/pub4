# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop"
require "tmpdir"

# A run's repair budget reaches thirty-odd of MASTER's files, so every run
# that started at the top repaired the same files again. The next run starts
# where the last one's budget ran out.
class TestStreamCursor < Minitest::Test
  Cursor = Master::Fix::FixLoop::StreamCursor

  def test_a_run_starts_where_the_last_one_stopped
    Dir.mktmpdir do |root|
      files = %w[a.rb b.rb c.rb d.rb].map { |name| File.join(root, "lib", name) }
      Cursor.write(root, File.join(root, "lib"), files[2])

      assert_equal files.values_at(2, 3, 0, 1), Cursor.order(root, File.join(root, "lib"), files)
    end
  end

  def test_a_stream_that_reached_the_end_clears_the_mark
    Dir.mktmpdir do |root|
      files = %w[a.rb b.rb].map { |name| File.join(root, name) }
      Cursor.write(root, root, files[1])
      Cursor.write(root, root, nil)

      assert_equal files, Cursor.order(root, root, files)
    end
  end

  def test_a_mark_for_a_file_that_is_gone_starts_at_the_top
    Dir.mktmpdir do |root|
      files = %w[a.rb b.rb].map { |name| File.join(root, name) }
      Cursor.write(root, root, File.join(root, "deleted.rb"))

      assert_equal files, Cursor.order(root, root, files)
    end
  end
end
