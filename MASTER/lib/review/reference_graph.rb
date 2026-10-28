# frozen_string_literal: true

require "find"
require "set"
require "digest"
require "prism"

module Master
  module Review
  # ReferenceGraph builds a lightweight semantic connectivity map
  # across the repository. This becomes the foundation for:
  # - safe rename
  # - precise rollback
  # - dead-file proof
  # - blast-radius estimation
  # - topology visualization
  # - governed autonomous restructuring
    class ReferenceGraph
      # Keep this graph aligned with FileCollector's eligible text corpus,
      # including extensionless build files, dotfiles, documentation and config.
      # Oversized or binary files are not source dependencies; /fix's inventory
      # reports their separate exclusion/blocking state.
      # Match the scanner's maximum readable source size. Repair context has
      # its own stricter combined budget; inventory must not silently omit a
      # larger eligible source and make the dependency map appear complete.
      MAX_TEXT_BYTES = 10 * 1024 * 1024
      PROBE_BYTES = 8 * 1024

      FALLBACK_IGNORE_DIRS = %w[
        .git .claude node_modules vendor tmp log coverage dist build .bundle
        .cache .next .output .turbo reports scratch site-packages venv .venv
        venv-demucs __pycache__ storage cache knowledge fixtures var
      ].freeze

      Edge = Struct.new(:type, :from, :to, :weight, keyword_init: true)

      # Prism-derived facts supplement imports with static symbol and caller
      # relationships. Ambiguous/dynamic relationships remain explicit evidence
      # gaps; a token match alone never proves a caller edge.
      class RubyVisitor < Prism::Visitor
        attr_reader :definitions, :references, :dynamic_sites

        def initialize(file:)
          @file = file
          @namespaces = []
          @methods = []
          @definitions = []
          @references = []
          @dynamic_sites = []
        end

        def visit_module_node(node)
          name = constant_name(node.constant_path)
          full = qualify(name)
          @definitions << definition(full, name.split("::").last, :module, node.location.start_line)
          @namespaces << full
          super
          @namespaces.pop
        end

        def visit_class_node(node)
          name = constant_name(node.constant_path)
          full = qualify(name)
          @definitions << definition(full, name.split("::").last, :class, node.location.start_line)
          if node.superclass
            @references << reference(
              node.superclass.location.start_line,
              :inheritance,
              constant_name(node.superclass),
              scope: @namespaces.last,
            )
          end
          @namespaces << full
          super
          @namespaces.pop
        end

        def visit_def_node(node)
          receiver_node = node.receiver
          receiver = if receiver_node.is_a?(Prism::SelfNode)
                       @namespaces.last
                     elsif receiver_node
                       constant_name(receiver_node)
                     end
          owner = receiver || @namespaces.last
          singleton = !receiver_node.nil?
          fqn = if owner
                  "#{owner}#{singleton ? "." : "#"}#{node.name}"
                else
                  "(top)##{node.name}"
                end
          @definitions << definition(fqn, node.name.to_s, :method, node.location.start_line,
                                     owner:, singleton:)
          @methods << { fqn:, owner:, singleton: }
          super
          @methods.pop
        end

        def visit_constant_write_node(node)
          name = qualify(node.name.to_s)
          @definitions << definition(name, node.name.to_s, :constant, node.location.start_line)
          super
        end

        def visit_constant_path_write_node(node)
          name = constant_name(node.target)
          @definitions << definition(name, name.split("::").last, :constant, node.location.start_line)
          super
        end

        def visit_constant_read_node(node)
          @references << reference(node.location.start_line, :constant, node.name.to_s,
                                   scope: @namespaces.last)
          super
        end

        def visit_constant_path_node(node)
          name = constant_name(node)
          @references << reference(node.location.start_line, :constant, name, scope: @namespaces.last)
          super
        end

        def visit_call_node(node)
          name = node.name.to_s
          scope = @namespaces.last
          receiver = receiver_name(node.receiver, scope)
          @references << reference(
            node.location.start_line,
            :call,
            name,
            receiver:,
            receiver_explicit: !node.receiver.nil?,
            scope:,
            caller: @methods.last && @methods.last[:fqn],
            singleton_scope: @methods.last && @methods.last[:singleton],
          )

          if %w[include prepend extend].include?(name) && node.receiver.nil?
            Array(node.arguments&.arguments).each do |argument|
              next unless constant_expression?(argument)

              @references << reference(node.location.start_line, :mixin, constant_name(argument), scope:)
            end
          end

          if %w[send public_send __send__].include?(name)
            target = literal_method_name(Array(node.arguments&.arguments).first)
            if target
              @references << reference(node.location.start_line, :dynamic_call, target,
                                       receiver:, receiver_explicit: !node.receiver.nil?, scope:,
                                       caller: @methods.last && @methods.last[:fqn])
            else
              @dynamic_sites << dynamic_site(node.location.start_line, name, "dynamic method name")
            end
          elsif %w[method_missing define_method define_singleton_method const_get const_missing
                   eval class_eval instance_eval module_eval].include?(name)
            @dynamic_sites << dynamic_site(node.location.start_line, name, "dynamic lookup or code evaluation")
          end

          super
        end

        private

        def definition(fqn, name, kind, line, owner: nil, singleton: false)
          { fqn:, name:, kind:, file: @file, line:, owner:, singleton: }
        end

        def reference(line, kind, name, receiver: nil, receiver_explicit: false, scope: nil,
                      caller: nil, singleton_scope: false)
          { from_file: @file, line:, kind:, name:, receiver:, receiver_explicit:, scope:, caller:, singleton_scope: }
        end

        def dynamic_site(line, name, reason)
          { file: @file, line:, name:, reason: }
        end

        def qualify(name)
          return name if name.include?("::") || @namespaces.empty?

          "#{@namespaces.last}::#{name}"
        end

        def constant_name(node)
          return "" unless node

          case node
          when Prism::ConstantReadNode
            node.name.to_s
          when Prism::ConstantPathNode, Prism::ConstantPathTargetNode
            node.slice.to_s
          else
            node.respond_to?(:slice) ? node.slice.to_s : (node.respond_to?(:name) ? node.name.to_s : "")
          end
        rescue StandardError
          ""
        end

        def receiver_name(node, scope)
          case node
          when nil
            nil
          when Prism::SelfNode
            scope
          when Prism::ConstantReadNode, Prism::ConstantPathNode, Prism::ConstantPathTargetNode
            constant_name(node)
          when Prism::CallNode
            # A constructor expression has a statically known receiver type:
            # SharedService.new.save can be linked to SharedService#save.
            node.name.to_s == "new" ? receiver_name(node.receiver, scope) : nil
          else
            nil
          end
        end

        def constant_expression?(node)
          node.is_a?(Prism::ConstantReadNode) ||
            node.is_a?(Prism::ConstantPathNode) ||
            node.is_a?(Prism::ConstantPathTargetNode)
        end

        def literal_method_name(node)
          return unless node.is_a?(Prism::SymbolNode) || node.is_a?(Prism::StringNode)

          raw = node.slice.to_s
          value = raw.sub(/\A:/, "").delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
          value if value.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[!?=]?\z/)
        end
      end

      attr_reader :nodes, :edges, :analysis_failures, :root

      def initialize(root:, event_bus: nil)
        @root = File.expand_path(root)
        @bus = event_bus
        @nodes = Set.new
        @edges = []
        @analysis_failures = []
        @source_digests = {}
        @ruby_definitions = []
        @ruby_references = []
        @path_references = []
        @dynamic_sites = []
        @unresolved_references = []
        @external_references = 0
        @built = false
        @build_lock = Mutex.new
      end

      # One complete source read builds the graph before repair. Repeated callers
      # reuse it; an operator-requested /fix explicitly refreshes it so stale
      # references from a previous run cannot authorize an edit.
      def build(refresh: false)
        @build_lock.synchronize do
          if refresh || !@built
            @nodes.clear
            @edges.clear
            @analysis_failures.clear
            @source_digests.clear
            @ruby_definitions.clear
            @ruby_references.clear
            @path_references.clear
            @dynamic_sites.clear
            @unresolved_references.clear
            @external_references = 0
            files.each { |file| analyze(file) }
            resolve_ruby_references!
            @built = true
          end

          graph = {
            nodes: @nodes.to_a.sort,
            edges: @edges.map(&:to_h),
            metrics:,
            analysis_failures: @analysis_failures.map(&:dup),
            ruby_definitions: @ruby_definitions.map(&:dup),
            unresolved_references: @unresolved_references.map(&:dup),
            dynamic_sites: @dynamic_sites.map(&:dup),
          }

          @bus&.publish(
            "reference_graph:built",
            nodes: graph[:nodes].size,
            edges: graph[:edges].size,
            analysis_failures: graph[:analysis_failures].size,
          )

          graph
        end
      end

      def blast_radius(path)
        rel = relative(path)
        impacted = @edges.select do |edge|
          (edge.to == rel && @nodes.include?(edge.from)) ||
            (edge.from == rel && @nodes.include?(edge.to))
        end
        {
          target: rel,
          inbound: impacted.select { |e| e.to == rel }.map(&:from).uniq.sort,
          outbound: impacted.select { |e| e.from == rel }.map(&:to).uniq.sort,
        }
      end

      # Caller/dependency edges derived from method names are conservative when
      # ambiguous. These gaps tell repair orchestration where more investigation
      # is needed; they must not be presented as an empty or complete call graph.
      def unresolved_for(path)
        rel = relative(path)
        target_names = @ruby_definitions.select { |row| row[:file] == rel && row[:kind] == :method }
                                        .map { |row| row[:name] }.to_set
        @unresolved_references.select do |row|
          dynamic = row[:receiver_explicit] || row[:kind] == :dynamic_call
          row[:from_file] == rel ||
            row[:kind] == :import ||
            (dynamic && %i[call dynamic_call].include?(row[:kind]) && target_names.include?(row[:name]))
        end.map(&:dup)
      end

      def dynamic_for(path)
        rel = relative(path)
        @dynamic_sites.select { |row| row[:file] == rel }.map(&:dup)
      end

      def source_digest(path)
        @source_digests[relative(path)]
      end

      private

      def files
        collected = []
        Find.find(@root) do |path|
          if File.directory?(path)
            Find.prune if File.symlink?(path) || skipped_by_scanner?(path)
            next
          end

          next if File.symlink?(path) || skipped_by_scanner?(path)
          next unless text_file?(path)

          collected << path
        end
        collected
      end

      # The fix corpus and the understanding graph must share path ownership.
      # Scanner owns generated/vendor exclusions. The local fallback is only for
      # isolated consumers that load ReferenceGraph without the fix runtime.
      def skipped_by_scanner?(path)
        return Master::Fix::Scanner.skip_path?(path, root: @root) if defined?(Master::Fix::Scanner)

        relative = File.expand_path(path).delete_prefix("#{@root}/")
        relative.split(File::SEPARATOR).any? { |segment| FALLBACK_IGNORE_DIRS.include?(segment) }
      end

      def text_file?(path)
        size = File.size(path)
        return false if size > MAX_TEXT_BYTES

        # binread returns nil at the end of an empty file, which a .gitkeep is.
        probe = File.binread(path, PROBE_BYTES).to_s
        return false if probe.include?("\0")

        # Extensionless source and dotfiles are common authoritative inputs
        # (Rakefile, Gemfile, Makefile, .gitignore). Include all readable text
        # instead of quietly narrowing the dependency graph by suffix.
        probe.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      rescue SystemCallError
        false
      end

      def analyze(file)
        rel = relative(file)
        @nodes << rel

        content = File.read(file, encoding: "UTF-8", invalid: :replace, undef: :replace)
        @source_digests[rel] = Digest::SHA256.hexdigest(content)

        ruby_requires(content, rel)
        constant_refs(content, rel)
        command_refs(content, rel)
        event_refs(content, rel)
        collect_path_references(content, rel)
        analyze_ruby(content, rel) if ruby_source?(rel, content:)
      rescue StandardError => e
        @analysis_failures << { path: rel.to_s, error: "#{e.class}: #{e.message}" }
        Master::Ground::Swallow.log(
          e,
          context: "reference_graph.analyze",
          event_bus: @bus,
          path: rel,
        )
      end

      def collect_path_references(content, rel)
        ext = File.extname(rel).downcase
        patterns = case ext
                   when ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx"
                     [
                       [:javascript_import, /\b(?:import|export)\s+(?:[^;\n]*?\s+from\s*)?["']([^"'\n]+)["']/],
                       [:javascript_import, /\brequire\s*\(\s*["']([^"'\n]+)["']\s*\)/],
                       [:javascript_import, /\bimport\s*\(\s*["']([^"'\n]+)["']\s*\)/],
                     ]
                   when ".css", ".scss"
                     [
                       [:stylesheet_import, /@(?:import|use|forward)\s+(?:url\(\s*)?["']([^"'\n]+)["']/],
                     ]
                   when ".html", ".htm", ".erb"
                     [
                       [:markup_import, /\b(?:src|href|poster|data)\s*=\s*["']([^"'\n]+)["']/i],
                     ]
                   else
                     []
                   end
        patterns.each do |kind, pattern|
          content.to_enum(:scan, pattern).each do
            match = Regexp.last_match
            specifier = match[1].to_s.strip
            next unless local_source_reference?(specifier, kind)

            line = content[0...match.begin(0)].count("\n") + 1
            @path_references << { from_file: rel, line:, kind: :import, source_kind: kind, name: specifier }
          end
        end
      end

      def local_source_reference?(specifier, kind)
        return false if specifier.empty?
        return false if specifier.match?(%r{\A(?:https?:|//|data:|mailto:|tel:|javascript:|#)}i)

        return false if specifier.start_with?("/")

        suffix = File.extname(specifier.split(/[?#]/, 2).first.to_s).downcase
        source_suffixes = %w[
          .js .jsx .mjs .cjs .ts .tsx .css .scss .html .htm .erb .json .yml .yaml .md .mdx
        ]
        return true if source_suffixes.include?(suffix)
        return true if kind == :stylesheet_import && !specifier.include?(":")
        return true if %i[javascript_import stylesheet_import markup_import].include?(kind) &&
                       specifier.start_with?("./", "../", "@/")

        false
      end

      def resolve_path_references!
        @path_references.each do |reference|
          specifier = reference[:name]
          resolved = resolve_local_source_path(reference[:from_file], specifier, source_kind: reference[:source_kind])
          if resolved
            edge(from: reference[:from_file], to: resolved, type: :local_import, weight: 1)
          else
            @unresolved_references << reference.merge(reason: "local source import did not resolve to an indexed file")
          end
        end
      end

      def resolve_local_source_path(from, specifier, source_kind: nil)
        clean = specifier.split(/[?#]/, 2).first.to_s
        base = if source_kind == :ruby_require_relative
                  File.expand_path(clean.delete_prefix("./"), File.dirname(File.join(@root, from)))
                elsif clean.start_with?("@/")
                  File.expand_path(clean.delete_prefix("@/"), @root)
                elsif clean.start_with?("./", "../") ||
                      %i[stylesheet_import markup_import].include?(source_kind)
                  File.expand_path(clean.delete_prefix("./"), File.dirname(File.join(@root, from)))
                else
                  return
                end
        candidates = [base]
        suffix = File.extname(base)
        if suffix.empty?
          %w[.js .jsx .mjs .cjs .ts .tsx .css .scss .html .htm .erb .json .yml .yaml .md .mdx].each do |extension|
            candidates << "#{base}#{extension}"
          end
          %w[index.js index.jsx index.mjs index.cjs index.ts index.tsx index.css index.scss index.html index.htm index.erb index.json].each do |name|
            candidates << File.join(base, name)
          end
        end
        candidates.map { |candidate| relative(candidate) }
                  .find { |candidate| @nodes.include?(candidate) }
      end

      def ruby_source?(rel, content:)
        return true if %w[.rb .rake .gemspec .ru].include?(File.extname(rel))
        return true if %w[Rakefile Gemfile Guardfile Podfile Appfile Fastfile].include?(File.basename(rel))

        content.lines.first.to_s.match?(/\A#!.*\bruby\b/)
      end

      def analyze_ruby(content, rel)
        parsed = Prism.parse(content)
        unless parsed.success?
          @analysis_failures << { path: rel, error: "Prism parse failed: #{parsed.errors.first&.message || "unknown syntax error"}" }
          return
        end

        visitor = RubyVisitor.new(file: rel)
        parsed.value.accept(visitor)
        @ruby_definitions.concat(visitor.definitions)
        @ruby_references.concat(visitor.references)
        @dynamic_sites.concat(visitor.dynamic_sites)
      end

      MAX_SPLIT_FILES = 8

      def resolve_ruby_references!
        methods = @ruby_definitions.select { |row| row[:kind] == :method }
        constants = @ruby_definitions.select { |row| %i[class module constant].include?(row[:kind]) }
        methods_by_name = methods.group_by { |row| row[:name] }
        methods_by_fqn = methods.group_by { |row| row[:fqn] }
        constants_by_fqn = constants.group_by { |row| row[:fqn] }
        constants_by_name = constants.group_by { |row| row[:name] }
        weights = Hash.new(0)

        @ruby_references.each do |reference|
          candidates = case reference[:kind]
                      when :call, :dynamic_call
                        resolve_method_reference(reference, methods_by_name, methods_by_fqn)
                      when :constant, :inheritance, :mixin
                        resolve_constant_reference(reference, constants_by_name, constants_by_fqn)
                      else
                        []
                      end

          next if candidates == :namespace

          candidates = candidates.uniq { |row| [row[:fqn], row[:file]] }
          if candidates.empty?
            note_unresolved(reference, external: external_reference?(reference, methods_by_name, constants_by_name))
            next
          end

          candidates.each do |candidate|
            next if candidate[:file] == reference[:from_file]

            edge_type = {
              call: :method_call,
              dynamic_call: :dynamic_method_call,
              constant: :constant_reference,
              inheritance: :inheritance,
              mixin: :mixin,
            }.fetch(reference[:kind])
            weights[[reference[:from_file], candidate[:file], edge_type]] += 1
          end
        end

        weights.each do |(from, to, type), weight|
          edge(from:, to:, type:, weight:)
        end
        resolve_path_references!
      end

      # A name the repository never defines (require_relative, Dir.pwd, each) points outside it: a gap in
      # nothing this graph could have known, and no reason to refuse a repair.
      def note_unresolved(reference, external:)
        if external
          @external_references += 1
        else
          @unresolved_references << reference.merge(reason: "no unique static source target")
        end

        nil
      end

      def external_reference?(reference, methods_by_name, constants_by_name)
        name = reference[:name].to_s
        case reference[:kind]
        when :call, :dynamic_call then methods_by_name[name].nil?
        else constants_by_name[name.split("::").last].nil?
        end
      end

      def resolve_method_reference(reference, by_name, by_fqn)
        name = reference[:name].to_s
        return [] if name.empty?

        receiver = reference[:receiver].to_s
        if !receiver.empty?
          exact = by_fqn.values_at("#{receiver}##{name}", "#{receiver}.#{name}").compact.flatten
          return exact unless exact.empty?
        elsif !reference[:receiver_explicit] && !reference[:scope].to_s.empty?
          scope = reference[:scope].to_s
          preferred = if reference[:singleton_scope]
                        by_fqn.values_at("#{scope}.#{name}", "#{scope}##{name}").compact.flatten
                      else
                        by_fqn.values_at("#{scope}##{name}", "#{scope}.#{name}").compact.flatten
                      end
          return preferred unless preferred.empty?
        end

        candidates = Array(by_name[name])
        unique_names = candidates.map { |row| row[:fqn] }.uniq
        return candidates if unique_names.one?

        []
      end

      def resolve_constant_reference(reference, by_name, by_fqn)
        name = reference[:name].to_s
        return [] if name.empty?

        exact = by_fqn[name]
        return spread_or_namespace(exact) if exact

        tail = name.split("::").last
        candidates = Array(by_name[tail])
        return spread_or_namespace(candidates) if candidates.map { |row| row[:fqn] }.uniq.one?

        []
      end

      # A class or module split over a few files depends on all of them. A name opened in many files,
      # such as Master or Master::CLI, is a scope and not a dependency on any one of them: counted as
      # one, a single reference tied a file to the whole tree (a million edges) and any dynamic call
      # anywhere put every repair in HUMAN_DECISION.
      def spread_or_namespace(rows)
        rows.map { |row| row[:file] }.uniq.size > MAX_SPLIT_FILES ? :namespace : rows
      end

      def ruby_requires(content, rel)
        content.to_enum(:scan, /\b(require_relative|require)\s+["']([^"']+)["']/).each do
          match = Regexp.last_match
          kind, target = match[1], match[2]
          if kind == "require_relative"
            line = content[0...match.begin(0)].count("\n") + 1
            @path_references << {
              from_file: rel,
              line:,
              kind: :import,
              source_kind: :ruby_require_relative,
              name: target,
            }
          end
          to = kind == "require_relative" ? resolve_relative_require(rel, target) : normalize_require(target)
          edge(from: rel, to:, type: :require, weight: 1.0)
        end
      end

      def constant_refs(content, rel)
        content.scan(/\b([A-Z][A-Za-z0-9_:]{2,})\b/).flatten.tally.each do |constant, count|
          edge(from: rel, to: "const:#{constant}", type: :constant, weight: count)
        end
      end

      def command_refs(content, rel)
        content.scan(%r{/[a-z_]+}).flatten.tally.each do |command, count|
          edge(from: rel, to: "command:#{command}", type: :command, weight: count)
        end
      end

      def event_refs(content, rel)
        content.scan(/["']([a-z_]+:[a-z_]+)["']/).flatten.tally.each do |event, count|
          edge(from: rel, to: "event:#{event}", type: :event, weight: count)
        end
      end

      def resolve_relative_require(rel, target)
        base = File.dirname(File.join(@root, rel))
        absolute = File.expand_path(target, base)
        relative = absolute.delete_prefix("#{@root}/")
        normalize_require(relative)
      end

      def normalize_require(target)
        cleaned = target.sub(%r{\A\./}, "")
        cleaned.end_with?(".rb") ? cleaned : "#{cleaned}.rb"
      end

      def edge(from:, to:, type:, weight:)
        @edges << Edge.new(
          type:,
          from:,
          to:,
          weight:,
        )
      end

      def metrics
        grouped = @edges.group_by(&:type)
        {
          node_count: @nodes.size,
          edge_count: @edges.size,
          require_edges: grouped.fetch(:require, []).size,
          constant_edges: grouped.fetch(:constant, []).size,
          resolved_constant_edges: grouped.fetch(:constant_reference, []).size,
          method_call_edges: grouped.fetch(:method_call, []).size,
          dynamic_method_call_edges: grouped.fetch(:dynamic_method_call, []).size,
          inheritance_edges: grouped.fetch(:inheritance, []).size,
          mixin_edges: grouped.fetch(:mixin, []).size,
          unresolved_ruby_references: @unresolved_references.count { |row| row[:kind] != :import },
          external_ruby_references: @external_references,
          unresolved_local_imports: @unresolved_references.count { |row| row[:kind] == :import },
          resolved_local_import_edges: grouped.fetch(:local_import, []).size,
          dynamic_sites: @dynamic_sites.size,
          event_edges: grouped.fetch(:event, []).size,
          command_edges: grouped.fetch(:command, []).size,
        }
      end

      def relative(path)
        # The separator is part of the prefix: /a/pub4x must not shed /a/pub4.
        File.expand_path(path).sub(%r{\A#{Regexp.escape(@root)}(?:/|\z)}, "")
      end

      public :relative

      def includes_path?(path)
        @nodes.include?(relative(path))
      end
      public :includes_path?
    end
  end
end
