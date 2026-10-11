# frozen_string_literal: true

module Master
  module Fix
    # The routes of one Rails app, read from config/routes.rb as text. `rails
    # routes` boots the app, which an offline sweep and a deploy canary cannot
    # count on; the file is the declaration, and this reads the shapes the repo's
    # route files use: verb lines, `resources`/`resource` with only/except,
    # `namespace`/`scope` nesting, `root`, and the shared route files pulled in
    # through `instance_eval(File.read(... "config/routes/<name>.rb" ...))`.
    #
    # Anything it cannot place exactly is marked rather than guessed: a route
    # with a dynamic segment is `parametric` (no URL can be built without data),
    # and one under a host or subdomain constraint is `constrained` (the canary
    # cannot know which Host header reaches it).
    class RoutesManifest
      Route = Data.define(:verb, :path, :controller, :action, :parametric, :constrained, :file)

      VERBS = %w[get post put patch delete].freeze
      RESOURCE_ACTIONS = %w[index new create show edit update destroy].freeze
      SINGULAR_ACTIONS = %w[new create show edit update destroy].freeze
      BLOCK_OPEN = /\A(?:if|unless|case|begin|while|until)\b|\bdo(?:\s*\|[^|]*\|)?\s*\z/
      Frame = Struct.new(:path, :module_name, :controller, :constrained, keyword_init: true)

      attr_reader :routes, :controllers

      def initialize(app_root:, shared_root: nil)
        @app_root = app_root
        @shared_root = shared_root
        @routes = []
        @controllers = []
        file = File.join(app_root, "config", "routes.rb")
        parse(file, [Frame.new]) if File.file?(file)
        @controllers.uniq!
      end

      # Paths a plain GET can reach: no dynamic segment, no host constraint.
      def public_get_paths
        routes.select { |r| r.verb == "get" && !r.parametric && !r.constrained }.map(&:path).uniq.sort
      end

      private

      def parse(file, stack)
        File.foreach(file, encoding: "UTF-8") { |raw| line(file, raw.strip, stack) }
      end

      def line(file, text, stack)
        text = text.sub(/\A#.*/, "").sub(/\s#\s[^"']*\z/, "")
        return if text.empty?

        if (shared = text[%r{config/routes/(\w+)\.rb}, 1]) && text.include?("instance_eval")
          include_shared(shared, stack)
        elsif text == "end"
          stack.pop if stack.size > 1
        elsif text.start_with?("namespace ")
          push(stack, text, path: symbol(text), module_name: symbol(text))
        elsif text.start_with?("scope")
          push(stack, text, path: text[/\Ascope\s*\(?\s*["']([^"']+)["']/, 1] || text[/\bpath:\s*["']([^"']+)["']/, 1],
                            module_name: text[/\bmodule:\s*["':](\w+)/, 1])
        elsif text.start_with?("resources ", "resource ")
          resource(file, text, stack)
        elsif text.match?(/\A(?:#{VERBS.join("|")}|root)\b/)
          verb_line(file, text, stack)
        elsif text.match?(/\A(?:member|collection|constraints)\b/) || text.match?(BLOCK_OPEN)
          push(stack, text, constrained: text.start_with?("constraints") || nil,
                            path: text.start_with?("member") ? ":id" : nil)
        end
      end

      def include_shared(name, stack)
        path = File.join(@shared_root.to_s, "config", "routes", "#{name}.rb")
        parse(path, stack) if @shared_root && File.file?(path)
      end

      # Only a line that opens a block pushes a frame, so the `end` that closes
      # it pops exactly one.
      def push(stack, text, **attrs)
        return unless text.match?(BLOCK_OPEN)

        stack.push(Frame.new(**attrs))
      end

      def symbol(text) = text[/\A\w+\s+:(\w+)/, 1]

      def resource(file, text, stack)
        singular = text.start_with?("resource ")
        names = text.sub(/\Aresources?\s+/, "").split(/,\s*/).take_while { |t| t.match?(/\A:\w+(?:\s+do)?\z/) }.map { |t| t[/\w+/] }
        names.each { |name| emit_resource(file, text, stack, name, singular) }
        push(stack, text, path: singular ? names.first.to_s : "#{names.first}/:#{names.first.to_s.sub(/s\z/, "")}_id",
                          controller: controller_of(text, names.first.to_s, singular), constrained: nil)
      end

      def emit_resource(file, text, stack, name, singular)
        controller = controller_of(text, name, singular)
        controller = [*modules(stack), controller].join("/")
        @controllers << controller
        actions = filter(singular ? SINGULAR_ACTIONS : RESOURCE_ACTIONS, text)
        base = text[/\bpath:\s*["']([^"']+)["']/, 1] || name
        actions.each do |action|
          suffix = get_suffix(action, singular) or next
          add(file, stack, "get", join(base, suffix), controller, action)
        end
      end

      # The path tail of a GET action; nil for the verbs that are not GET.
      def get_suffix(action, singular)
        case action
        when "index" then ""
        when "new" then "new"
        when "show" then singular ? "" : ":id"
        when "edit" then singular ? "edit" : ":id/edit"
        end
      end

      def controller_of(text, name, singular)
        text[/\bcontroller:\s*["':]([\w\/]+)/, 1] || (singular ? plural(name) : name)
      end

      # `resource :session` is served by SessionsController.
      def plural(name) = name.end_with?("s") ? name : "#{name}s"

      def filter(all, text)
        only = list(text, "only")
        except = list(text, "except")
        (only || all) - (except || [])
      end

      def list(text, key)
        raw = text[/\b#{key}:\s*(%i\[[^\]]*\]|%w\[[^\]]*\]|\[[^\]]*\]|:\w+)/, 1] or return
        raw.sub(/\A%[iw]/, "").scan(/\w+/)
      end

      def verb_line(file, text, stack)
        verb = text[/\A\w+/]
        target = text[/["']([\w\/]+)#(\w+)["']/]
        if target
          name, action = target.delete("\"'").split("#")
          controller = [*modules(stack), name].join("/")
        elsif (name = stack.reverse.map(&:controller).compact.first)
          controller = [*modules(stack), name].join("/")
        end
        @controllers << controller if controller
        if verb == "root"
          return add(file, stack, "get", "", controller, action)
        end

        path = text[/\A\w+\s*\(?\s*["']([^"']+)["']/, 1] || text[/\A\w+\s+:(\w+)/, 1]
        add(file, stack, verb, path.to_s, controller, action || path.to_s) if path
        push(stack, text)
      end

      def modules(stack) = stack.map(&:module_name).compact

      def join(*parts) = parts.reject { |p| p.to_s.empty? }.join("/")

      def add(file, stack, verb, path, controller, action)
        full = "/" + join(*stack.map(&:path), path.to_s.delete_prefix("/")).squeeze("/")
        full = full.sub(%r{(?<=.)/\z}, "")
        @routes << Route.new(verb:, path: full, controller:, action:,
                             parametric: full.match?(/[:*(]/),
                             constrained: stack.any?(&:constrained) || false, file:)
      end
    end
  end
end
