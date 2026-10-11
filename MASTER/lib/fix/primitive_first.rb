# frozen_string_literal: true

module Master
  module Fix
    # A visual fix belongs in the shared primitive, not in a page that happens
    # to show the defect. When a finding's selector appears on two or more
    # pages, PrimitiveFirst names the stylesheet rule that owns it and refuses
    # a patch that overrides that rule under a page scope. It also notes where
    # new page CSS rebuilds a layout primitive the shared layer already has.
    # Nested scss is not parsed: only flat rules are checked.
    module PrimitiveFirst
      SHARED_DIR = File.join("RAILS", "__shared", "app", "assets", "stylesheets")
      MIN_PAGES = 2
      CSS_EXT = %w[.css .scss].freeze
      CLASS_RE = /\.(-?[A-Za-z_][\w-]*)/
      RULE_RE = /([^{}]+)\{/
      PART_RE = /#[\w-]+|\[[^\]]*\]|\.[\w-]+|[a-z][\w-]*/
      # A simple selector that names one page rather than one component.
      PAGE_PART_RE = /\A(?:body|html|#[\w-]+|\[data-(?:page|route|controller|action)[^\]]*\]|\.(?:page|screen|view|route)(?:-[\w-]+)?|\.\w+-(?:page|index|show|new|edit))\z/
      LAYOUT_ADVICE = {
        /display:\s*flex[^}]*flex-direction:\s*column[^}]*gap|flex-direction:\s*column[^}]*display:\s*flex[^}]*gap/m => "stack",
        /display:\s*flex[^}]*flex-wrap:\s*wrap[^}]*gap|flex-wrap:\s*wrap[^}]*display:\s*flex[^}]*gap/m => "cluster",
        /display:\s*grid[^}]*repeat\(\s*auto-(?:fit|fill)/m => "auto-grid",
      }.freeze

      module_function

      def repo_root(root) = File.basename(root.to_s) == "MASTER" ? File.dirname(root.to_s) : root.to_s

      # Prompt text for a visual finding, or nil when the selector is not a
      # class on two pages or its owning rule cannot be found.
      def hint(violation, root:)
        root = repo_root(root)
        selector = violation[:anchor].to_s
        name = selector[/\A\.(.+)\z/, 1]
        return unless name

        pages = pages_using(name, root:, extra: Array(violation[:surfaces]))
        return if pages.size < MIN_PAGES

        owner = owner_of(name, root:, near: violation[:file])
        return unless owner

        "PRIMITIVE-FIRST: #{selector} appears on #{pages.size} pages (#{pages.first(4).join(", ")}). " \
          "Edit the primitive at #{owner}; do not add page-scoped overrides."
      end

      # A reason to reject the patch, or nil. Advice about layout primitives is
      # logged and never rejects: it cannot change a rendered value.
      def check(path, old_src, new_src, root:)
        return unless CSS_EXT.include?(File.extname(path.to_s).downcase)
        return if path.to_s.include?("/#{SHARED_DIR}/")

        root = repo_root(root)
        before = bodies(old_src)
        added = bodies(new_src).reject { |rule| before.include?(rule) }
        advise(added, root:)
        override_of(added.map(&:first), root:)
      end

      def override_of(added, root:)
        shared = shared_classes(root)
        added.each do |selector|
          selector.split(",").map(&:strip).each do |single|
            owned = single.scan(CLASS_RE).flatten.select { |name| shared.key?(name) }
            return "page-scoped override of shared primitive .#{owned.first} (#{single})" if owned.any? && page_scoped?(single, shared)
          end
        end
        nil
      end

      # True when a compound before the last one names a page. A compound like
      # "body.page-home" counts; a class the shared layer defines does not.
      def page_scoped?(selector, shared)
        compounds = selector.split(/\s*[>+~]\s*|\s+/).reject(&:empty?)
        compounds[0...-1].to_a.any? do |compound|
          compound.scan(PART_RE).any? { |part| PAGE_PART_RE.match?(part) && !shared.key?(part.delete_prefix(".")) }
        end
      end

      def advise(added, root:)
        defined = shared_classes(root)
        added.each do |selector, body|
          primitive = LAYOUT_ADVICE.find { |re, _| body.match?(re) }&.last
          next unless primitive && defined.key?(primitive)

          Master::Trace::Dmesg.status("prim0", "#{selector} rebuilds .#{primitive}; prefer the shared class in markup")
        end
      rescue StandardError, NameError
        nil
      end

      def bodies(src)
        src.to_s.scan(/([^{}]+)\{([^{}]*)\}/).map { |sel, body| [sel.gsub(/\s+/, " ").strip, body] }
           .reject { |sel, _| sel.empty? || sel.start_with?("@") }
      end

      # Distinct view files in the repo that mention the class, plus any
      # surfaces the cross-page overlay or cross-app report already named.
      def pages_using(name, root:, extra: [])
        pattern = /(?<![\w-])#{Regexp.escape(name)}(?![\w-])/
        views = Dir.glob(File.join(root, "RAILS", "**", "app", "views", "**", "*.erb")).select do |file|
          File.foreach(file, encoding: "UTF-8").any? { |line| line.match?(pattern) }
        end
        (views.map { |file| file.delete_prefix("#{root}/") } + extra.map(&:to_s)).uniq
      end

      # "path:line" of the first rule line in the shared layer that defines the
      # class, else in the app's own application.scss.
      def owner_of(name, root:, near: nil)
        candidates = Dir.glob(File.join(root, SHARED_DIR, "*.scss")).sort
        app = near.to_s[%r{RAILS/([^/]+)/}, 1]
        candidates << File.join(root, "RAILS", app, "app", "assets", "stylesheets", "application.scss") if app
        candidates.each do |file|
          next unless File.file?(file)

          line = definition_line(file, name)
          return "#{file.delete_prefix("#{root}/")}:#{line}" if line
        end
        nil
      end

      def definition_line(file, name)
        pattern = /(?:\A|[\s,>+~(])\.#{Regexp.escape(name)}(?![\w-])/
        File.foreach(file, encoding: "UTF-8").with_index(1) do |text, number|
          return number if text.match?(pattern) && !text.lstrip.start_with?("//", "/*", "*") && text.match?(/[{,]\s*\z/)
        end
        nil
      end

      def shared_classes(root)
        Dir.glob(File.join(root, SHARED_DIR, "*.scss")).each_with_object({}) do |file, found|
          File.read(file, encoding: "UTF-8").scan(RULE_RE).flatten.each do |selector|
            selector.scan(CLASS_RE).flatten.each { |name| found[name] = true }
          end
        end
      end
    end
  end
end
