# frozen_string_literal: true

require_relative "rails_app"

module Master
  module Fix
    # Does a repaired Rails view, stylesheet or script still compile? The rescan reads a broken
    # template as fine, the render check needs the apps up, and the committer parses Ruby only.
    # Views and stylesheets compile under brgen's bundle (tools/rails/compile_check.rb): every app
    # pins one Rails commit, and only brgen's bundle also holds sass-embedded. nil means it compiles.
    module SourceCompile
      CHECKER = File.expand_path("../../tools/rails/compile_check.rb", __dir__)

      IN_APP = %w[.erb .scss .css].freeze
      RAILS_PATH = %r{\A(?<rails>.+/RAILS)/(?<component>[^/]+)/}
      SKIPPED = %r{/(?:vendor|builds|node_modules|tmp)/}
      COMPILER_APP = "brgen"

      module_function

      def failure(path)
        found = path.to_s.match(RAILS_PATH)
        return if found.nil? || path.to_s.match?(SKIPPED)

        ext = File.extname(path).downcase
        return script_failure(path) if ext == ".js"
        return unless IN_APP.include?(ext)

        app = File.join(found[:rails], COMPILER_APP)
        out, status = RailsApp.capture(app, "bundle", "exec", "ruby", CHECKER, path, *entries(found, ext), timeout: 120)
        status.success? || status.exitstatus == 2 ? nil : out.strip[0, 300]
      end

      # A module is read as one from stdin: `node --check file.js` passed a module whose function
      # head never closed, since a .js file is tried as CommonJS first. A classic script keeps the
      # plain check.
      MODULE = /^\s*(?:import|export)\b/

      def script_failure(path)
        source = File.read(path, encoding: "UTF-8")
        command = source.match?(MODULE) ? %w[node --input-type=module --check] : ["node", "--check", path]
        out, status = Master::Io::Exec.capture2e(*command, stdin_data: source, timeout: 30)
        status.success? ? nil : "#{File.basename(path)}: #{out.lines.grep(/Error/).first.to_s.strip[0, 200]}"
      rescue Errno::ENOENT
        raise "source_compile: node is not installed, so #{File.basename(path)} cannot be checked"
      end

      # A partial is judged by the entries that import it: its own app's, brgen's for a vertical,
      # or every app's for the shared engine, whose partials each app's build loads. An app with
      # no application.scss (master) has its stylesheet compiled on its own.
      def entries(found, ext)
        return [] unless ext == ".scss"

        apps = found[:component] == "__shared" ? "*" : found[:component].sub(/\Abrgen_.+\z/, "brgen")
        Dir.glob(File.join(found[:rails], apps, "app", "assets", "stylesheets", "application.scss"))
      end
    end
  end
end
