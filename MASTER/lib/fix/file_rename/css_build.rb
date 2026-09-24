# frozen_string_literal: true

require "open3"

module Master
  module Fix
    class FileRename
      # The proof for a stylesheet rename: every app's application.scss compiled
      # before and after, with /* */ comments removed, must be the same rules.
      # Comments are removed because a comment that names the renamed file is
      # emitted into the CSS and changes its bytes without changing a rule.
      # Dart Sass through npx, the way the face bundles build with esbuild.
      module CssBuild
        APPS = %w[amber brgen bsdports].freeze
        SASS = "sass@1.93.2"

        def self.rules(repo_root)
          rails = File.join(repo_root, "RAILS")
          APPS.to_h do |app|
            out, err, status = Open3.capture3("npx", "--yes", SASS, "--no-source-map", "--quiet",
                                              "--load-path=#{app}/app/assets/stylesheets",
                                              "--load-path=shared/app/assets/stylesheets",
                                              "#{app}/app/assets/stylesheets/application.scss", chdir: rails)
            raise "sass failed for #{app}: #{err.lines.first(3).join}" unless status.success?

            [app, out.gsub(%r{/\*.*?\*/}m, "")]
          end
        end
      end
    end
  end
end
