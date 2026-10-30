# frozen_string_literal: true

require "prism"

module Master
  module Review
    module Scan
      require_relative "finding"
      require_relative "source_masking"
      require_relative "../../master"

      # What a deterministic detector runs inside: the helpers every detector
      # shares (findings, AST walks, source masking) and nothing about which Law
      # it serves. A Law's identity, severity and tags come from its
      # Law::Definition; a `check` block runs on one of these, and a detector
      # class a Law names with `detector` is one of these.
      class Detector
        include SourceMasking

        EXT_LANG = Master::FILE_LANGUAGE_MAP

        attr_reader :id, :description, :severity, :law_tags, :auto_fix, :definition

        # Whether a finding depends on more than the file's text and path: git history,
        # sibling files, another tree. Scan::FindingCache replays a pure detector's findings
        # for unchanged content, so one that reads further must say so here.
        def self.reads_beyond_file? = false

        def reads_beyond_file? = self.class.reads_beyond_file? || definition&.reads_beyond_file ? true : false

        # law/ writes :warn where the scanner reports :warning.
        def self.normalize_severity(value) = value.to_sym == :warn ? :warning : value.to_sym

        # What the scanner hands a detector class it builds: each class takes the
        # keywords its constructor names (root:, agent:, ecology:) and no others.
        # This read each class's name against a regex in LawFactory, which is how
        # a new detector with an unlisted constructor raised ArgumentError at boot.
        CONTEXT = %i[root agent ecology].freeze

        def self.build(definition, root: Master::ROOT, agent: nil, ecology: nil)
          context = { root:, agent:, ecology: }
          accepted = instance_method(:initialize).parameters.filter_map do |kind, name|
            name if %i[key keyreq].include?(kind) && CONTEXT.include?(name)
          end
          new(**context.slice(*accepted)).bind(definition)
        end

        # A detector class built directly (`GodClassLaw.new`) still judges for the
        # one Law that names it, so it binds to that definition here; build binds
        # again with the same answer. A `check` block's runner has no Law until bound.
        def initialize
          @id = ""
          @description = ""
          @severity = :warning
          @law_tags = []
          @auto_fix = false
          definition = self.class.law_definition
          bind(definition) if definition
        end

        def self.law_definition
          return unless defined?(::Law.definitions) && self != Detector

          ::Law.definitions.each_value.find { |definition| definition.detector == self }
        end

        # A detector judges for exactly one Law, and takes everything it reports
        # under (id, severity, tags, autofix permission) from that Law's definition.
        def bind(definition)
          @definition = definition
          @id = definition.id.to_s
          @description = (definition.ask || definition.fix).to_s
          @severity = self.class.normalize_severity(definition.severity)
          @law_tags = definition.tags.empty? ? [@id] : definition.tags
          @auto_fix = definition.autofix == :automatic
          self
        end

        def mode = definition ? definition.mode : :violation

        def languages = definition ? Array(definition.languages).map(&:to_s) : []

        # Work a detector can do for a whole walk before it reads each file; the linter laws batch their runs.
        def prefetch(_paths) = nil

        def autofix = auto_fix

        # Default for AST-based detectors: a subclass implements check_ast and gets
        # this for free. Detectors with non-AST logic override #check instead.
        def check(code, path:)
          raise NotImplementedError, "#{self.class}#check not implemented" unless respond_to?(:check_ast)

          return [] unless path.to_s.end_with?(".rb", ".rake")

          check_ast(Prism.parse(code).value, code, path:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "#{self.class}#check_ast", severity: :load_bearing, path:)
          raise "law #{@id} AST check failed: #{e.class}: #{e.message}"
        end

        def language(path) = Master.language_for(path)

        # Prepended to every Laws::NeedsModel detector, so it runs in front of the
        # detector's own rescue. A missing agent is how the scanner was built, not a
        # model fault: raised inside that rescue it wrote a load_bearing swallow row
        # per file (3,627 a run), and returned as [] it read as an answer of clean.
        module AgentGuard
          def agent? = !@agent.nil?

          def check(code, path:)
            return super if agent?

            raise "semantic assessment INCONCLUSIVE: no model agent configured for #{path}"
          end
        end

        def applies_to?(path, languages)
          return true if languages.nil? || languages.empty?
          lang = language(path)
          lang && languages.include?(lang)
        end

        protected

        # A repair that creates or merges files. RepairLoop returns one file per
        # answer, so such a finding goes to a person (needs_a_person?) instead
        # of costing model calls that can only come back UNCHANGED.
        SPANS_FILES = { files_touched: 2 }.freeze

        # Changing a signature changes every call to it. A private method's
        # callers are in its own file; a public one's may be anywhere, which
        # a one-file repair cannot see, so Opus declined every such finding.
        def signature_radius(lines, index)
          return if lines[index].to_s.match?(/\A\s*(?:private|protected)\s+def\b/)

          visibility = lines.first(index).reverse.find { |line| line.match?(/\A\s*(?:private|protected|public)\s*\z/) }
          visibility.to_s.strip == "public" || visibility.nil? ? SPANS_FILES : nil
        end

        def finding(line:, message:, fix: nil, confidence: nil, why: nil, genealogy: nil, impact_radius: nil,
                    dedupe_key: nil, blast_radius: nil)
          Finding.build(
            law: @id,
            message:,
            line:,
            severity: @severity,
            fix:,
            tags: @law_tags,
            confidence: confidence || default_confidence,
            why: why || default_why(message),
            genealogy: genealogy || default_genealogy(message),
            dedupe_key: dedupe_key || default_dedupe_key(message),
            impact_radius:,
            blast_radius:,
          )
        end

        # Every node under this detector, in source order. Ten rules in
        # structural_rules.rb each carried a byte-identical private `visit` doing
        # exactly this — the copy-paste the old backlog names as "one shared AST-walk
        # helper". They call this now, and a fix to the traversal lands once.
        def walk(node, &block)
          return unless node.respond_to?(:child_nodes)

          block.call(node)
          node.child_nodes.compact.each { |child| walk(child, &block) }
        end

        # Every node of one Prism type. The filter over the walk above, so the
        # two cannot disagree about what "under this node" means.
        def each_node(node, type, acc = [])
          walk(node) { |child| acc << child if child.is_a?(type) }
          acc
        end

        # The parameter names a def declares, positional then keyword, in the
        # order they are written.
        def parameter_names(def_node)
          params = def_node.parameters
          return [] unless params

          (Array(params.requireds) + Array(params.optionals) + Array(params.keywords))
            .filter_map { |param| param.name&.to_s if param.respond_to?(:name) }
        end

        # Blocks opened by one keyword, as [first_line, source] pairs. Lexical on
        # purpose: the laws that read this ask how large a def or a class is,
        # and they must answer on a file Prism will not parse.
        def keyword_blocks(code, keyword)
          opener = /\A\s*#{keyword}\b/
          result = []
          current = nil
          code.each_line.with_index(1) do |line, index|
            current = [index, +""] if line.match?(opener)
            current[1] << line if current
            if current && line.match?(/\A\s*end\b/)
              result << current
              current = nil
            end
          end
          result
        end

        def scan_lines(code, pattern, message:, fix: nil)
          code.each_line.with_index(1).filter_map do |line, num|
            # The law engine honours the same marker: a line that declares
            # itself intentional carries a reviewer's reason beside it.
            next if line.match?(SCAN_MARKER)
            finding(line: num, message:, fix:) if line.match?(pattern)
          end
        end

        # The marker is a trailing comment, and adding one lengthens the line it
        # sits on. Two rules measure exactly those two things, so exempting a
        # line correctly used to buy a LONG_LINE and a TRAILING_COMMENT — 135
        # findings across the tree, every one of them created by an author doing
        # the right thing.
        #
        # Laws that measure the shape of a line read it without its marker. A
        # line still too long with the marker removed is still too long.
        #
        # The marker can share its comment with other machine directives —
        # `-- scan: intentional` is one
        # comment carrying two instructions — so the exemption is the whole
        # comment the marker sits in, found by walking back from the marker to
        # whichever opener began it. Walking back rather than matching forward
        # is what keeps a `#` inside a string literal from being read as the
        # start of the comment.
        COMMENT_OPENERS = ["#", "//", "/*", "<!--", "<%#"].freeze
        SCAN_MARKER = /scan:\s*intentional\b/

        def without_scan_marker(line)
          text = line.chomp
          marker = text.index(SCAN_MARKER)
          return text unless marker

          opener = COMMENT_OPENERS.filter_map { |token| text.rindex(token, marker) }.max
          return text unless opener

          text[0, opener].rstrip
        end

        def default_confidence
          case @severity
          when :error then 0.9
          when :warning then 0.78
          else 0.62
          end
        end

        def default_why(message)
          "#{message} because it tends to increase maintenance risk and regression cost."
        end

        def default_genealogy(message)
          [@law_tags.first || "GENERAL", @id, message.to_s.split(" — ").first.to_s]
        end

        def default_dedupe_key(message)
          "#{@id}:#{message.to_s.downcase.gsub(/\b\d+\b/, "#")}"
        end
      end
    end
  end
end
