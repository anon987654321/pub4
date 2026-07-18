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

  def test_honors_only_actions_and_plural_resource_helpers
    with_app do |app|
      write_routes(app, 'resources :widgets, only: %i[index show]')
      write_controller(app, "widgets", <<~RUBY)
        class WidgetsController < ApplicationController
          def index; end
          def show; end
        end
      RUBY
      write_view(app, "widgets/index", "<%= widget_path(@widget) %>")
      write_view(app, "widgets/show", "ok")

      violations = @audit.audit(app).fetch(:violations)
      refute violations.any? { |v| %i[missing_action missing_view unknown_path_helper].include?(v[:id]) }, violations.inspect
    end
  end

  def test_only_treats_rendering_as_action_specific
    with_app do |app|
      write_routes(app, 'get "widgets/:id", to: "widgets#show"')
      write_controller(app, "widgets", <<~RUBY)
        class WidgetsController < ApplicationController
          def index
            render plain: "ok"
          end

          def show; end
        end
      RUBY

      ids = @audit.audit(app).fetch(:violations).map { |v| v[:id] }
      assert_includes ids, :missing_view
    end
  end

  def test_resolves_scoped_resource_controller
    with_app do |app|
      write_routes(app, <<~RUBY)
        scope module: "admin" do
          resources :reports, only: :index
        end
      RUBY
      write_controller(app, "admin/reports", <<~RUBY)
        class Admin::ReportsController < ApplicationController
          def index; end
        end
      RUBY
      write_controller(app, "reports", <<~RUBY)
        class ReportsController < ApplicationController
          def show; end
        end
      RUBY
      write_view(app, "admin/reports/index", "ok")

      violations = @audit.audit(app).fetch(:violations)
      refute violations.any? { |v| %i[missing_controller missing_action missing_view].include?(v[:id]) }, violations.inspect
    end
  end

  def test_loads_routes_and_actions_from_shared_files
    with_app do |app|
      shared = File.join(File.dirname(app), "shared", "config", "routes")
      FileUtils.mkdir_p(shared)
      File.write(File.join(shared, "included.rb"), 'get "status", to: "statuses#show"')
      write_routes(app, 'instance_eval(File.read(File.expand_path("../../shared/config/routes/included.rb", __dir__)))')
      write_controller(app, "statuses", <<~RUBY)
        class StatusesController < ApplicationController
          def show
            render plain: "ok"
          end
        end
      RUBY

      violations = @audit.audit(app).fetch(:violations)
      refute violations.any? { |v| %i[missing_controller missing_action missing_view].include?(v[:id]) }, violations.inspect
    end
  end

  def test_loads_actions_from_included_shared_concerns
    with_app do |app|
      write_routes(app, 'get "status", to: "statuses#show"')
      concern = File.join(File.dirname(app), "shared", "app", "controllers", "concerns", "shared")
      FileUtils.mkdir_p(concern)
      File.write(File.join(concern, "status_actions.rb"), <<~RUBY)
        module Shared
          module StatusActions
            def show
              render plain: "ok"
            end
          end
        end
      RUBY
      write_controller(app, "statuses", <<~RUBY)
        class StatusesController < ApplicationController
          include Shared::StatusActions
        end
      RUBY

      violations = @audit.audit(app).fetch(:violations)
      refute violations.any? { |v| %i[missing_action missing_view].include?(v[:id]) }, violations.inspect
    end
  end

  private

  def with_app
    Dir.mktmpdir do |tmpdir|
      app = File.join(tmpdir, "demo")
      FileUtils.mkdir_p(File.join(app, "config"))
      FileUtils.mkdir_p(File.join(app, "app", "controllers"))
      FileUtils.mkdir_p(File.join(app, "app", "views"))
      yield app
    end
  end

  def write_routes(app, body)
    File.write(File.join(app, "config", "routes.rb"), "Rails.application.routes.draw do\n#{body}\nend\n")
  end

  def write_controller(app, name, body)
    path = File.join(app, "app", "controllers", "#{name}_controller.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def write_view(app, name, body)
    path = File.join(app, "app", "views", "#{name}.html.erb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end
end
