# frozen_string_literal: true

require "test_helper"

class PostproJobTest < ActiveSupport::TestCase
  test "postpro script resolves to DEPLOY/postpro/postpro.rb" do
    expected = Rails.root.join("../../postpro/postpro.rb").expand_path
    assert_equal expected, PostproJob::POSTPRO
    assert File.file?(PostproJob::POSTPRO), "expected postpro at #{PostproJob::POSTPRO}"
  end
end