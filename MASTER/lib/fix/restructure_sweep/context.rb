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
        RELATED_LINES = 180

        # [path, rule_id, message, related_paths] for every actionable structural finding.
        def self.structural_findings(target)
          rules = structural_rules(target)
          local = tracked(target).flat_map do |path|
            code = File.read(path, encoding: "UTF-8")
            rules.flat_map { |rule| rule.check(code, path:) }.map { |f| [path, f[:rule].to_s, f[:message].to_s, []] }
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.findings", path:)
            []
          end
          local + cross_file_findings(target) + dead_subtree_findings(target)
        end

        def self.dead_subtree_findings(target)
          return [] unless File.basename(target.to_s) == "MASTER"

          source = production_files(target)
          subtrees = Dir.glob(File.join(target.to_s, "lib", "**", "*")).select(&:directory?).filter_map do |dir|
            next if dir == File.join(target.to_s, "lib")
            next if dir.split("/").any? { |part| %w[test spec fixtures vendor].include?(part) }

            all = Dir.glob(File.join(dir, "**", "*.{rb,rake,js,mjs}")).select(&:file?)
            next if all.size < 3

            needles = all.flat_map { |path| names_in_file(path) }.uniq
            outside = source - all
            referenced = outside.any? do |path|
              code = File.read(path, encoding: "UTF-8")
              needles.any? { |needle| code.match?(needle) }
            rescue StandardError
              false
            end
            next if referenced

            first = all.first
            [first, "DEAD_SUBTREE", "#{relative_static(first, target)} subtree has #{all.size} production source files and no production references from outside the subtree", all]
          end
          subtrees.sort_by { |_path, _rule, message, _files| [message[/\d+/].to_i, message] }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "restructure.dead_subtree", target:)
          []
        end

        def self.names_in_file(path)
          stem = File.basename(path, ".*")
          constants = File.read(path, encoding: "UTF-8")
            .scan(/^\s*(?:class|module)\s+([A-Z][\w:]+)/).flatten
          [stem.length >= 4 ? Regexp.new(Regexp.escape(stem)) : nil,
           *constants.map { |name| Regexp.new("\\b#{Regexp.escape(name)}\\b") }].compact
        rescue StandardError
          []
        end

        def self.relative_static(path, target)
          path.to_s.delete_prefix("#{target}/")
        end

        def self.cross_file_findings(target)
          rows = Master::Review::Scan::CrossFileAnalysis.new(root: target).call(production_files(target))
          findings = rows.flat_map { |_path, result| result.value_or([]) }
          findings.filter_map do |finding|
            next unless %w[PARALLEL_HIERARCHY CYCLIC_DEPENDENCY].include?(finding[:rule].to_s)

            related = finding[:impact_radius].is_a?(Hash) ? Array(finding[:impact_radius][:files]) : []
            path = related.first
            next unless path

            [path, finding[:rule].to_s, finding[:message].to_s, related]
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "restructure.cross_file_findings", target:)
          []
        end

        def self.structural_rules(target)
          scan = Master::Review::Scan
          scan::RuleDSL
          js = scan::Rule.registry.find { |klass| klass.name.nil? && klass.new.id == "JS_MODULE_SIZE" }
          [scan::Rules::GodClassRule.new, scan::Rules::SmallFilesRule.new,
           scan::Rules::FileSprawlRule.new(root: target), js&.new].compact
        end

        def self.repository_files(root)
          out, status = Master::Io::Exec.capture2e("git", "-C", root.to_s, "ls-files")
          return [] unless status.success?

          out.lines.map { |line| File.join(root.to_s, line.strip) }.select(&:file?)
        end

        def self.production_files(root)
          repository_files(root).select do |path|
            SOURCE_EXT.include?(File.extname(path)) &&
              !path.split("/").any? { |part| %w[test spec fixtures].include?(part) } &&
              !Master::Review::Scan::Scanner.skip_path?(path, root: root.to_s)
          end
        end

        def self.tracked(target)
          out, = Master::Io::Exec.capture2e("git", "-C", target.to_s, "ls-files")
          out.lines.map { |line| File.join(target.to_s, line.strip) }.select do |path|
            SOURCE_EXT.include?(File.extname(path)) && File.file?(path) &&
              !Master::Review::Scan::Scanner.skip_path?(path, root: target.to_s)
          end
        end

        def initialize(repo_root, path, related: [])
          @root = repo_root
          @path = path
          @related = Array(related)
          @tree = File.join(repo_root, relative(path).split("/").first)
        end

        def to_s
          [inventory_section, history_section, file_section, related_section, directory_section, owner_section,
           reference_section, production_reference_section, requirer_section].compact.join("\n\n")
        end

        private

        def inventory_section
          tracked = Context.repository_files(@root)
          source = Context.tracked(@tree)
          counts = source.group_by { |path| relative(path).split("/").first }.transform_values(&:size)
          "Tree census: #{tracked.size} tracked files repo-wide; #{source.size} source files here; #{counts.map { |tree, count| "#{tree}=#{count}" }.join(", ")}"
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

        def related_section
          paths = @related.reject { |path| path == @path }.first(4)
          return if paths.empty?

          rows = paths.map do |path|
            lines = File.foreach(path).first(RELATED_LINES)
            suffix = File.foreach(path).count > RELATED_LINES ? "
... truncated at #{RELATED_LINES} lines" : ""
            "Related file, #{relative(path)}:\n#{numbered_lines(lines)}#{suffix}"
          rescue StandardError
            "Related file, #{relative(path)}"
          end
          rows.join("\n\n")
        end

        def numbered_lines(lines)
          lines.each_with_index.map { |line, index| format("%4d  %s", index + 1, line) }.join
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
          @production_references ||= Context.production_files(@root)
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

        def test_path?(path)
          path.split("/").any? { |part| %w[test spec fixtures].include?(part) }
        end

        def numbered(path) = File.foreach(path).with_index(1).map { |line, n| format("%4d  %s", n, line) }.join
        def relative(path) = path.to_s.delete_prefix("#{@root}/")
      end
    end
  end
end
