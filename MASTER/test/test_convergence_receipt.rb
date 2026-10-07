# frozen_string_literal: true

require_relative "test_helper"
require "json"
require_relative "../lib/convergence/receipt"

class TestConvergenceReceipt < Minitest::Test
  def test_receipt_contains_identity_and_inventory
    Dir.mktmpdir do |dir|
      %w[MASTER RAILS OPENBSD STUDIO].each { |tree| FileUtils.mkdir_p(File.join(dir, tree)) }
      FileUtils.mkdir_p(File.join(dir, "MASTER", "data"))
      File.write(File.join(dir, "MASTER", "data", "soul.yml"), "schema: 1\n")
      File.write(File.join(dir, "MASTER", "data", "laws.yml"), "ROBUSTNESS: {priority: 1, principle: safe}\n")
      result = Master::Convergence::Receipt.write(root: dir, command: "test", state: :pass, details: { hello: :world })
      body = JSON.parse(File.read(result[:path]))
      assert_equal "test", body["command"]
      assert_equal "pass", body["state"]
      assert_equal "world", body.dig("details", "hello")
      assert_equal 4, body.dig("inventory", "trees").size
      assert_equal 64, result[:sha256].length
    end
  end
end
