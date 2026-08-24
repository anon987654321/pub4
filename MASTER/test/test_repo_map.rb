# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class TestRepoMap < Minitest::Test
  def test_brief_respects_token_budget
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      10.times { |index| File.write(File.join(dir, "lib", "file_#{index}.rb"), "puts :ok\n") }

      rows = Master::Ground::Map::Repo.new(root: dir).brief("file", limit: 10, token_limit: 8)

      assert rows.any?
      assert_operator rows.join("\n").bytesize, :<=, 40
    end
  end
end
