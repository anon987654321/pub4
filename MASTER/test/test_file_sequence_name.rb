# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "review/scan/law_tree"

# FILE_SEQUENCE_NAME fires only when a sibling shares the stem: a sequence word
# lies only when there is another version of the same thing beside it.
class FileSequenceNameTest < Minitest::Test
  def law = Master::Review::Scan::LawTree.find(:FILE_SEQUENCE_NAME)

  def check(dir, name)
    File.write(File.join(dir, name), "x = 1\n")
    law.check("x = 1\n", path: File.join(dir, name))
  end

  def test_a_versioned_sibling_is_a_finding
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "importer.rb"), "x = 1\n")
      found = check(dir, "importer_v2.rb")

      assert_equal 1, found.size
      assert_match(/'v2' says when, not what/, found.first[:message])
    end
  end

  def test_a_lone_versioned_file_is_its_own_subject
    Dir.mktmpdir do |dir|
      assert_empty check(dir, "upgrade_to_v1_10.rb")
    end
  end

  def test_migrations_keep_their_rails_names
    Dir.mktmpdir do |dir|
      migrate = File.join(dir, "db", "migrate")
      FileUtils.mkdir_p(migrate)
      File.write(File.join(migrate, "add_thing.rb"), "x = 1\n")

      assert_empty check(migrate, "add_thing_v2.rb")
    end
  end
end
