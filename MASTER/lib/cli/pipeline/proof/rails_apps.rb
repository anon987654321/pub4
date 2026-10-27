# frozen_string_literal: true

require "pathname"
require_relative "../../../fix/rails_app"
require_relative "../../../io/exec"

module Master
  module CLI
    class Pipeline
      module Proof
        # What a pass changed in a Rails app, proved in that app under its own bundle: it boots,
        # and the tests that name a changed file pass. The RAILS proof was MASTER's static checks
        # alone, so a renamed constant in brgen stood until the closing bin/ci.

        # Each app is its own suite in the output, so the judge holds its failures against the
        # baseline as it does every suite's. A vertical is proved in brgen, the shared engine in all.
        module RailsApps
          TEST_ENV = { "RAILS_ENV" => "test" }.freeze
          LIMIT = 40
          TIMEOUT_S = 900
          EXCLUDED_TESTS = %r{/test/(?:system|dummy|fixtures)/}

          module_function

          # [held, lines] for the RAILS paths (relative to the repository root) a pass changed.
          def prove(paths, repo_root: Master::REPO_ROOT)
            runs = apps_for(paths, repo_root:).map { |app, changed| prove_app(app, changed, repo_root:) }
            [runs.all?(&:first), runs.flat_map(&:last)]
          end

          def apps_for(paths, repo_root:)
            named = Master::Fix::RailsApp.named_apps(repo_root:)
            engine = Master::Fix::RailsApp.engine_apps(repo_root:)
            paths.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |path, apps|
              owners(path, named:, engine:).each { |app| apps[app] << path }
            end
          end

          def owners(path, named:, engine:)
            component = path[%r{\ARAILS/([^/]+)/}, 1]
            return [] unless component
            return engine if component == "__shared"
            return ["brgen"] if component.start_with?("brgen_") && named.include?("brgen")

            named.include?(component) ? [component] : []
          end

          def prove_app(app, changed, repo_root:)
            root = File.join(repo_root, "RAILS", app)
            booted, lines = boot(app, root)
            tests = booted ? tests_for(app, changed, repo_root:) : []
            tested, test_lines = tests.empty? ? [true, []] : run_tests(app, root:, tests:)
            held = booted && tested
            [held, ["proof suite #{app}: #{held ? "ok" : "FAIL"}", *lines, *test_lines]]
          end

          def boot(app, root)
            label, *commands = boot_check(root)
            out, status = commands.reduce(nil) { |last, args| last && !last.last.success? ? last : run(root, *args) }
            ok = status.success?
            [ok, ["#{app}: #{label}: #{ok ? "ok" : "FAIL"}", *(ok ? [] : out.lines.last(6).map(&:chomp))]]
          end

          def run_tests(app, root:, tests:)
            out, status = run(root, "test", *tests)
            [status.success?, ["#{app}: #{tests.size} test file(s)", *out.lines.map(&:chomp)]]
          end

          # Production eager-loads, so the proof does: zeitwerk:check. The master app never does (its
          # production.rb: MASTER's own loader trips Zeitwerk), so there it proves that the app boots.
          LAZY = /^\s*config\.eager_load\s*=\s*false/

          # [label, command, ...]: the commands run in order and stop at the first that fails.
          def boot_check(root)
            production = File.join(root, "config", "environments", "production.rb")
            return ["boots and eager-loads", %w[db:prepare zeitwerk:check]] unless
              File.file?(production) && File.read(production).match?(LAZY)

            ["boots", %w[db:prepare], ["runner", "puts Rails.application.class.name"]]
          end

          def run(root, *args)
            Master::Fix::RailsApp.capture(root, "bin/rails", *args, timeout: TIMEOUT_S, env: TEST_ENV)
          end

          # The changed test files, each changed file's own test, and the tests that name a changed
          # file's constant, relative to the app root; capped, since the closing bin/ci runs them all.
          def tests_for(app, changed, repo_root:)
            root = File.join(repo_root, "RAILS", app)
            found = candidates(app, changed, repo_root:, root:).uniq.select { |path| runnable?(path) }
            found.sort.first(LIMIT).map { |path| Pathname(path).relative_path_from(Pathname(root)).to_s }
          end

          def candidates(app, changed, repo_root:, root:)
            absolute = changed.map { |path| File.join(repo_root, path) }
            test_roots(app, repo_root:).flat_map { |dir| naming(changed, dir) } +
              absolute.select { |path| path.end_with?("_test.rb") } +
              absolute.filter_map { |path| own_test(path, root) }
          end

          def runnable?(path) = File.file?(path) && !path.match?(EXCLUDED_TESTS)

          def own_test(path, root)
            app, test = Master::Fix::RepairLoop::FixVerification.rails_test_for(path)
            File.expand_path(test, app) if app == root
          end

          def naming(changed, dir)
            constants = changed.select { |path| path.end_with?(".rb") }.map { |path| constant(path) }.uniq
            return [] if constants.empty? || !File.directory?(dir)

            args = constants.flat_map { |name| ["-e", name] }
            out, status = Master::Io::Exec.capture2("git", "grep", "-l", "-w", *args, "--", ".", chdir: dir)
            status.success? ? out.split("\n").grep(/_test\.rb\z/).map { |file| File.join(dir, file) } : []
          end

          def constant(path) = File.basename(path, ".rb").split("_").map(&:capitalize).join

          # brgen's suite reaches its verticals and the shared engine (__shared/config/test_scope.rb).
          def test_roots(app, repo_root:)
            rails = File.join(repo_root, "RAILS")
            own = [File.join(rails, app, "test")]
            return own unless app == "brgen"

            own + Dir.glob(File.join(rails, "brgen_*", "**", "test")) + [File.join(rails, "__shared", "test")]
          end
        end
      end
    end
  end
end
