# frozen_string_literal: true

require "test_helper"

class PostproJobTest < ActiveSupport::TestCase
  test "postpro script resolves to DEPLOY/postpro/postpro.rb" do
    script = PostproJob::POSTPRO
    assert script, "postpro script not found in #{Pub4::DeployPaths.postpro_candidates.map(&:expand_path)}"
    assert_includes script.to_s, "/DEPLOY/postpro/postpro.rb"
    assert File.file?(script), "expected postpro at #{script}"
  end
end