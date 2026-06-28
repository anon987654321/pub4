# frozen_string_literal: true

require_relative "test_helper"

class TestUnifiedDiffEditor < Minitest::Test
  def test_parser_records_hunks_and_summary
    Dir.mktmpdir do |root|
      File.write(File.join(root, "file.rb"), "old\n")
      editor = Master::Ground::UnifiedDiffEditor.new(root:)
      diff = "--- a/file.rb\n+++ b/file.rb\n@@ -1,1 +1,1 @@\n-old\n+new\n"

      assert editor.applyable?(diff)
      assert_equal "file.rb +1 -1 hunks=1", editor.summary(diff).first
    end
  end

  def test_path_traversal_is_not_applyable
    editor = Master::Ground::UnifiedDiffEditor.new(root: Dir.mktmpdir)
    diff = "--- a/../outside.rb\n+++ b/../outside.rb\n@@ -1 +1 @@\n-old\n+new\n"
    refute editor.applyable?(diff)
  end
end
