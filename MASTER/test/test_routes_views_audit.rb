# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "master"

class RoutesViewsAuditTest < Minitest::Test
  def setup
    @audit = Master::Rails::RoutesViewsAudit.new
    @amber = File.join(Master::DEPLOY_RAILS, "amber")
  end

  def test_audit_returns_violation_structure
    skip "amber not present" unless Dir.exist?(@amber)

    result = @audit.audit(@amber)
    assert result.key?(:violations)
    assert result.key?(:counts)
    assert result[:violations].all? { |v| v.key?(:id) && v.key?(:severity) && v.key?(:file) && v.key?(:message) }
  end

  def test_detects_missing_controller_on_fake_route
    Dir.mktmpdir do |tmpdir|
      app = File.join(tmpdir, "demo")
      FileUtils.mkdir_p(File.join(app, "config"))
      FileUtils.mkdir_p(File.join(app, "app", "views"))
      File.write(File.join(app, "config", "routes.rb"), <<~RUBY)
        Rails.application.routes.draw do
          get "ghost" => "ghosts#index"
        end
      RUBY

      result = @audit.audit(app)
      ids = result[:violations].map { |v| v[:id].to_s }
      assert_includes ids, "missing_controller"
    end
  end
end