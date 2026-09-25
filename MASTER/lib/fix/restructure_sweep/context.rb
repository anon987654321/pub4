# frozen_string_literal: true

module Master
  module Fix
    class RestructureSweep
      # What the model sees before it proposes a restructure: the file, its
      # directory, the files it might merge into, and every line elsewhere that
      # names it, with the requiring files in full because a move rewrites them.
      class Context
        SOURCE_EXT = %w[.rb .rake .js .mjs].freeze
        REFERENCE_LINES = 80
        REQUIRERS = 5
        SMALL = 400

        # [path, rule_id, message] for every structural finding under target.
        def self.structural_findings(target)
          rules = structural_rules(target)
          tracked(target).flat_map do |path|
            code = File.read(path, encoding: "UTF-8")
            rules.flat_map { |rule| rule.check(code, path:) }.map { |f| [path, f[:rule].to_s, f[:message].to_s] }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.findings", path:)
            []
          end
        end

        def self.structural_rules(target)
          scan = Master::Review::Scan
          scan::RuleDSL
          js = scan::Rule.registry.find { |klass| klass.name.nil? && klass.new.id == "JS_MODULE_SIZE" }
          [scan::Rules::GodClassRule.new, scan::Rules::SmallFilesRule.new,
           scan::Rules::FileSprawlRule.new(root: target), js&.new].compact
        end

        def self.tracked(target)
          out, = Master::Io::Exec.capture2e("git", "-C", target.to_s, "ls-files")
          out.lines.map { |line| File.join(target.to_s, line.strip) }.select do |path|
            SOURCE_EXT.include?(File.extname(path)) && File.file?(path) &&
              !Master::Review::Scan::Scanner.skip_path?(path, root: target.to_s)
          end
        end

        def initialize(repo_root, path)
          @root = repo_root
          @path = path
          @tree = File.join(repo_root, relative(path).split("/").first)
        end

        def to_s
          [inventory_section, history_section, file_section, directory_section, owner_section,\n           reference_section, production_reference_section, requirer_section].compact.join("\n\n")
        end

        private

        def inventory_section
          rows = Context.tracked(@tree)
          counts = rows.group_by { |path| relative(path).split("/").first }.transform_values(&:size)
          "Tree census: #{rows.size} tracked source files; #{counts.map { |tree, count| "#{tree}=#{count}" }.join(", ")}"
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "restructure.inventory")
          nil
        end

        def history_section
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "log", "--format=%h %s", "-8", "--", relative(@path))
          return if !status.success? || out.to_s.strip.empty?

          "Recent history for #{relative(@path)}:\n#{out.strip}"
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "restructure.history", path: @path)
          nil
        end

        def file_section
          "The file, #{relative(@path)}:\n#{numbered(@path)}"
        end

        def directory_section
          dir = File.dirname(@path)
          rows = Dir.children(dir).sort.map do |name|
            full = File.join(dir, name)
            File.directory?(full) ? "#{name}/" : "#{name} (#{File.foreach(full).count} lines)"
          end
          "Its directory, #{relative(dir)}/:\n#{rows.join("\n")}"
        end

        # A tiny file merges into its owner: the file named for its directory,
        # or a small sibling.
        def owner_section
          dir = File.dirname(@path)
          owners = ["#{dir}.rb", *Dir.glob(File.join(dir, "*.rb"))].uniq.reject { |path| path == @path }
                     .select { |path| File.file?(path) && File.foreach(path).count <= SMALL }.first(3)
          return if owners.empty?

          owners.map { |path| "Possible owner, #{relative(path)}:\n#{numbered(path)}" }.join("\n\n")
        end

        def production_reference_section
          hits = production_references.flat_map do |path, lines|
            lines.map { |number, text| "#{relative(path)}:#{number}: #{text.strip[0, 160]}" }
          end
          return if hits.empty?

          "Production references:\n#{hits.first(REFERENCE_LINES).join("\n")}"
        end

        def reference_section
          hits = references.flat_map do |path, lines|
            lines.map { |number, text| "#{relative(path)}:#{number}: #{text.strip[0, 160]}" }
          end
          return if hits.empty?

          "Lines elsewhere that name it:\n#{hits.first(REFERENCE_LINES).join("\n")}"
        end

        def requirer_section
          requirers = references.keys.select { |path| File.read(path).match?(require_pattern) }
                                .select { |path| File.foreach(path).count <= SMALL }.first(REQUIRERS)
          return if requirers.empty?

          requirers.map { |path| "Requires it, in full, #{relative(path)}:\n#{numbered(path)}" }.join("\n\n")
        end

        # { path => [[line_number, text]] } for files that name the stem or a constant.
        def production_references
          @production_references ||= Context.tracked(@tree)
            .reject { |path| path == @path || test_path?(path) }
            .to_h do |path|
              [path, File.foreach(path).with_index(1).select { |text, _n| text.match?(needle) }.map(&:reverse)]
            rescue ArgumentError
              [path, []]
            end.reject { |_path, lines| lines.empty? }
        end

        def references
          @references ||= Context.tracked(@tree).reject { |path| path == @path }.to_h do |path|
            [path, File.foreach(path).with_index(1).select { |text, _n| text.match?(needle) }.map(&:reverse)]
          rescue ArgumentError
            [path, []]
          end.reject { |_path, lines| lines.empty? }
        end

        def needle
          @needle ||= Regexp.union([require_pattern, *constants.map { |name| /\b#{name}\b/ }])
        end

        def require_pattern
          stem = Regexp.escape(File.basename(@path, ".*"))
          /require(?:_relative)?\s*\(?\s*["'][^"']*\b#{stem}["']/
        end

        def constants
          File.read(@path).scan(/^\s*(?:class|module)\s+([A-Z]\w+)/).flatten.uniq - Restructure.namespaces(@tree)
        end

        def numbered(path) = File.foreach(path).with_index(1).map { |line, n| format("%4d  %s", n, line) }.join
        def relative(path) = path.to_s.delete_prefix("#{@root}/")
      end
    end
  end
end
