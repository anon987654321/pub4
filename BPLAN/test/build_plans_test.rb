#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "bplan/validate"

class BuildPlansTest < Minitest::Test
  def setup
    @root = File.expand_path("..", __dir__)
  end

  def test_build_plans_runs_clean
    out, err, status = Open3.capture3("ruby", "build_plans.rb", chdir: @root)
    assert status.success?, "build_plans failed:\n#{out}\n#{err}"
    assert_match(/validated venture budgets/, out)
  end

  def test_plans_exist_after_build
    Bplan::Constants::PLAN_ORDER.each do |slug|
      path = File.join(@root, "#{slug}.html")
      assert File.exist?(path), "missing #{slug}.html after build"
    end
  end
end