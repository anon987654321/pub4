# frozen_string_literal: true

require "set"
require_relative "routes_manifest"

module Master
  module Fix
    # Routes that cannot be served and views nothing can reach, read from the
    # route manifest and the file tree alone.
    #
    #   dead route    its controller class file exists nowhere (app, shared, engines),
    #                 or the action has neither a `def` nor a template.
    #   unreachable   a non-partial template whose directory is no routed
    #   view          controller and which no `render` names.
    #
    # Both are candidates for a human: a controller can be reopened by an engine
    # or a gem this scan does not see, so nothing here deletes.
    class DeadRouteSweep
      FRAMEWORK_CONTROLLERS = %r{\A(?:rails|active_storage|action_mailbox|turbo|devise)/}
      INFRASTRUCTURE_DIRS = %w[layouts shared pwa mailers kaminari errors].freeze

      Candidate = Data.define(:kind, :app, :subject, :detail)

      # app_roots: { "brgen" => path }; shared_root joins every app's lookup.
      def initialize(app_roots:, shared_root:, corpus_text: nil)
        @app_roots = app_roots
        @shared_root = shared_root
        @manifests = app_roots.to_h { |name, root| [name, RoutesManifest.new(app_root: root, shared_root:)] }
        @corpus_text = corpus_text
      end

      attr_reader :manifests

      def candidates
        @app_roots.flat_map { |app, root| dead_routes(app, root) + unreachable_views(app, root) }
      end

      private

      def dead_routes(app, root)
        manifests.fetch(app).routes.filter_map do |route|
          next if route.controller.nil? || route.controller.match?(FRAMEWORK_CONTROLLERS)

          file = controller_file(route.controller, lookup_roots(root))
          if file.nil?
            Candidate.new(:dead_route, app, "#{route.verb.upcase} #{route.path}", "controller #{route.controller} has no class file")
          elsif route.action && !action?(file, route, lookup_roots(root))
            Candidate.new(:dead_route, app, "#{route.verb.upcase} #{route.path}", "#{route.controller}##{route.action} has no def and no template")
          end
        end
      end

      # Engines mounted into an app serve its routes, so every tree is searched.
      def lookup_roots(root) = [root, @shared_root, *@app_roots.values].compact.uniq

      def controller_file(controller, roots)
        # An isolated engine serves `likes` from controllers/dating/likes_controller.rb.
        roots.compact.flat_map { |r| Dir.glob(File.join(r, "app", "controllers", "{,*/}#{controller}_controller.rb")) }.first
      end

      # An action is real when its controller defines it, a template renders
      # for it, or the controller inherits from a base other than
      # ApplicationController, which this scan does not read.
      def action?(file, route, roots)
        return true if File.read(file, encoding: "UTF-8").match?(/\bdef\s+#{Regexp.escape(route.action)}\b/)
        return true if defined_actions(roots).include?(route.action)
        return true if roots.compact.any? { |r| Dir.glob(File.join(r, "app", "views", route.controller, "#{route.action}.*")).any? }
        return true if File.read(file, encoding: "UTF-8").match?(/<\s*(?!ApplicationController\b)[A-Z]\w*/)

        false
      end

      # Every `def` in any controller or concern: an action may live in a shared
      # concern the controller includes, so a name match anywhere counts.
      def defined_actions(roots)
        @defined ||= {}
        @defined[roots] ||= roots.flat_map { |r| Dir.glob(File.join(r, "{app/controllers,lib}", "**", "*.rb")) }
                                 .flat_map { |p| File.read(p, encoding: "UTF-8").scan(/\bdef\s+(\w+[?!]?)/).flatten }.to_set
      end

      def unreachable_views(app, root)
        routed = routed_controllers(app, root)
        Dir.glob(File.join(root, "app", "views", "**", "*.erb")).filter_map do |path|
          rel = path.delete_prefix(File.join(root, "app", "views") + "/")
          dir = File.dirname(rel)
          name = File.basename(rel).split(".").first
          next if name.start_with?("_") || dir == "." || INFRASTRUCTURE_DIRS.include?(dir.split("/").first)
          next if dir.end_with?("_mailer") || routed?(routed, dir) || rendered?(dir, name)

          Candidate.new(:unreachable_view, app, rel, "no route reaches #{dir} and no render names #{dir}/#{name}")
        end
      end

      def routed?(routed, dir) = routed.any? { |c| dir == c || dir.end_with?("/#{c}") }

      def routed_controllers(app, _root)
        manifests.fetch(app).controllers
      end

      def rendered?(dir, name)
        @corpus_text.to_s.include?("#{dir}/#{name}") || @corpus_text.to_s.match?(/render[ (]+(?:template:\s*)?["']#{Regexp.escape(name)}["']/)
      end
    end
  end
end
