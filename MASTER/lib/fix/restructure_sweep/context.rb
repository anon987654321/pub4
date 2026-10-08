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
        PROSE_EXTENSIONS = %w[.md .txt].freeze
        COMMAND_EXTENSIONS = %w[.rb .rake .sh .zsh].freeze
        COMMAND_ROOTS = %w[bin tools].freeze
        CONFIG_EXTENSIONS = %w[.rb .rake .yml .yaml .json].freeze
        STALE_PATHS = %w[RAILS/shared RAILS/mobile RAILS/visual_contract RAILS/contracts RAILS/brgen/engines].freeze

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
          local + cross_file_findings(target) + dead_subtree_findings(target) + surface_findings(target)
        end

        def self.dead_subtree_findings(target)
          return [] unless File.basename(target.to_s) == "MASTER"

          source = production_files(target)
          subtrees = Dir.glob(File.join(target.to_s, "lib", "**", "*")).select { |path| File.directory?(path) }.filter_map do |dir|
            dead_subtree(dir, target, source)
          end
          subtrees.sort_by { |_path, _rule, message, _files| [message[/\d+/].to_i, message] }
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "restructure.dead_subtree", target:)
          []
        end

        # One directory's finding, or nil while anything outside it names it.
        def self.dead_subtree(dir, target, source)
          return if dir == File.join(target.to_s, "lib")
          return if dir.split("/").any? { |part| %w[test spec fixtures vendor].include?(part) }

          all = Dir.glob(File.join(dir, "**", "*.{rb,rake,js,mjs}")).select { |path| File.file?(path) }
          return if all.size < 3

          needles = all.flat_map { |path| names_in_file(path) }.uniq
          return if referenced_outside?(source - all, needles)

          first = all.first
          [first, "DEAD_SUBTREE", "#{relative_static(first, target)} subtree has #{all.size} production source files and no production references from outside the subtree", all]
        end

        def self.referenced_outside?(outside, needles)
          outside.any? do |path|
            code = File.read(path, encoding: "UTF-8")
            needles.any? { |needle| code.match?(needle) }
          rescue StandardError
            false
          end
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

        private_class_method :dead_subtree, :referenced_outside?, :names_in_file, :relative_static

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

        def self.surface_findings(target)
          stale_reference_findings(target) + prose_findings(target) + command_surface_findings(target) + route_surface_findings(target) + config_surface_findings(target)
        end

        def self.stale_reference_findings(target)
          rows = repository_files(target).filter_map do |path|
            text = File.read(path, encoding: "UTF-8")
            matches = STALE_PATHS.select { |needle| text.include?(needle) }
            matches.empty? ? nil : [path, matches]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.stale_reference", path:)
            nil
          end
          rows.filter_map do |path, matches|
            related = rows.select { |_other, other_matches| (matches & other_matches).any? }
                        .map(&:first).reject { |other| other == path }.first(8)
            [path, "STALE_PATH_REFERENCE", "#{matches.length} retired topology reference(s): #{matches.join(", ")}", related]
          end
        end

        def self.prose_findings(target)
          paragraphs = Hash.new { |hash, key| hash[key] = [] }
          repository_files(target).select { |path| PROSE_EXTENSIONS.include?(File.extname(path).downcase) }.each do |path|
            File.read(path, encoding: "UTF-8").split(/\n\s*\n+/).each do |block|
              next if block.lstrip.start_with?("```") || block.include?("\n```")
              normalized = block.lines.map(&:strip).reject(&:empty?).join(" ").downcase.gsub(/\s+/, " ").strip
              next if normalized.length < 120 || normalized.split.length < 20
              paragraphs[normalized] << path
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.prose", path:)
          end
          paragraphs.filter_map do |_paragraph, paths|
            paths = paths.uniq
            next if paths.size < 2
            paths.map do |path|
              [path, "PROSE_DUPLICATION", "prose paragraph is duplicated across #{paths.size} files", paths.reject { |other| other == path }.first(8)]
            end
          end.flatten(1)
        end

        def self.route_surface_findings(target)
          repository_files(target).select { |path| File.basename(path) == "routes.rb" }.filter_map do |path|
            text = File.read(path, encoding: "UTF-8")
            helpers = text.scan(/\bas:\s*:([a-z][a-z0-9_]*)/i).flatten
            duplicates = helpers.tally.select { |_name, count| count > 1 }.keys
            next if duplicates.empty?

            [path, "ROUTE_SURFACE_DUPLICATION", "route helper(s) declared more than once: #{duplicates.join(", ")}", []]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.routes", path:)
            nil
          end
        end

        def self.config_surface_findings(target)
          repository_files(target).filter_map do |path|
            relative = relative_static(path, target)
            next unless relative.split("/").include?("config") && CONFIG_EXTENSIONS.include?(File.extname(path).downcase)

            text = File.read(path, encoding: "UTF-8")
            keys = text.scan(/^\s*config\.x\.([A-Za-z0-9_]+)\s*=/).flatten
            duplicates = keys.tally.select { |_name, count| count > 1 }.keys
            next if duplicates.empty?

            [path, "CONFIG_SURFACE_DUPLICATION", "config.x setting(s) assigned more than once: #{duplicates.join(", ")}", []]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.config", path:)
            nil
          end
        end

        def self.command_surface_findings(target)
          signatures = repository_files(target).filter_map do |path|
            relative = relative_static(path, target)
            ext = File.extname(path).downcase
            root = relative.split("/").first
            next unless COMMAND_EXTENSIONS.include?(ext) && (COMMAND_ROOTS.include?(root) || relative.include?("/bin/"))

            text = File.read(path, encoding: "UTF-8")
            commands = []
            text.scan(/^\s*when\s+["\x27]([a-z][a-z0-9_:-]*)["\x27]/i) { |match| commands << match.first.downcase }
            text.scan(/\bCOMMANDS\s*=\s*%i\[([^\]]+)\]/) { |match| commands.concat(match.first.scan(/[a-z][a-z0-9_:-]*/i).map(&:downcase)) }
            commands = commands.uniq.sort
            next if commands.empty?
            [path, commands]
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "restructure.commands", path:)
            nil
          end
          signatures.group_by { |_path, commands| commands }.values
            .select { |group| group.size > 1 }.flat_map do |group|
              group.map do |path, commands|
                [path, "COMMAND_SURFACE_DUPLICATION", "command surface #{commands.join(", ")} is duplicated across #{group.size} executables", group.map(&:first).reject { |other| other == path }.first(8)]
              end
            end
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

          out.lines.map { |line| File.join(root.to_s, line.strip) }.select { |path| File.file?(path) }
        end

        def self.production_files(root)
          repository_files(root).select do |path|
            SOURCE_EXT.include?(File.extname(path)) &&
              !path.split("/").any? { |part| %w[test spec fixtures].include?(part) } &&
              !Master::Fix::Scanner.skip_path?(path, root: root.to_s)
          end
        end

        def self.tracked(target)
          out, = Master::Io::Exec.capture2e("git", "-C", target.to_s, "ls-files")
          out.lines.map { |line| File.join(target.to_s, line.strip) }.select do |path|
            SOURCE_EXT.include?(File.extname(path)) && File.file?(path) &&
              !Master::Fix::Scanner.skip_path?(path, root: target.to_s)
          end
        end

        def initialize(repo_root, path, related: [])
          @root = repo_root
          @path = path
          @related = Array(related)
          @tree = File.join(repo_root, relative(path).split("/").first)
        end

        def to_s
          [surface_section, inventory_section, history_section, file_section, related_section, directory_section, owner_section,
           reference_section, production_reference_section, requirer_section].compact.join("\n\n")
        end

        private

        def surface_section
          extension = File.extname(@path).downcase
          relative = relative(@path)
          kind = if PROSE_EXTENSIONS.include?(extension)
                   "prose"
                 elsif File.basename(@path) == "routes.rb"
                   "route"
                 elsif relative.split("/").include?("config") && CONFIG_EXTENSIONS.include?(extension)
                   "config"
                 elsif COMMAND_EXTENSIONS.include?(extension) && relative.split("/").any? { |part| COMMAND_ROOTS.include?(part) }
                   "command"
                 else
                   "code"
                 end
          "Surface: #{kind}; /fix may consolidate one concept across its filesystem, code, prose, route, command and configuration forms when evidence supports it."
        end

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
          out, status = Master::Io::Exec.capture2e("git", "-C", @root, "log", "--all", "--follow", "--format=%h %s", "-12", "--", relative(@path))
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
