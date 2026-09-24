# frozen_string_literal: true

module Master
  module Fix
    class Restructure
      # Each app a restructure touches still passes Rails' own zeitwerk:check,
      # and when a stylesheet moved, every app compiles to the same CSS rules.
      # RAILS/shared is the mixin engine all three apps mount, so a change there
      # is proved in all three.
      class RailsProof < Proof
        APPS = %w[brgen amber bsdports].freeze
        # The test database, prepared first: a checkout has no development
        # database, and some controllers read the users table as they load.
        TEST_ENV = { "RAILS_ENV" => "test" }.freeze

        private

        def tree_baseline(plan) = stylesheets?(plan) ? FileRename::CssBuild.rules(@repo_root) : nil

        def tree_failure(plan, before)
          zeitwerk_failure(plan) || css_failure(before)
        end

        def zeitwerk_failure(plan)
          apps(plan).each do |app|
            out, status = rails(app, "db:prepare")
            out, status = rails(app, "zeitwerk:check") if status.success?
            return "#{app} fails zeitwerk:check: #{out.lines.last(3).join.strip[0, 300]}" unless status.success?
          end
          nil
        end

        def css_failure(before)
          return unless before

          after = FileRename::CssBuild.rules(@repo_root)
          changed = before.keys.reject { |app| before[app] == after[app] }
          "compiled CSS changed for #{changed.join(", ")}" unless changed.empty?
        end

        def apps(plan)
          named = plan.paths.flat_map do |path|
            app = path.split("/")[1]
            app == "shared" ? APPS : [app]
          end
          named.uniq & APPS
        end

        def stylesheets?(plan) = plan.paths.any? { |path| path.end_with?(".scss", ".css") }

        def test_files(plan)
          apps(plan).flat_map { |app| Dir.glob(File.join(@tree_root, app, "test", "**", "*_test.rb")) }
        end

        # brgen/test/models/post_test.rb runs as `bin/rails test` inside brgen.
        def run_test(test)
          app, rest = test.split("/", 2)
          rails(app, "test", rest)
        end

        def rails(app, *args)
          RailsApp.capture(File.join(@tree_root, app), "bin/rails", *args, timeout: TIMEOUT_S, env: TEST_ENV)
        end
      end
    end
  end
end
