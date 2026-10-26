# frozen_string_literal: true

require "prism"

module Master
  module Review
  module Scan
    require_relative "finding"
    require_relative "source_masking"
    require_relative "../../master"

      class Law
        include SourceMasking

        EXT_LANG = Master::FILE_LANGUAGE_MAP

        attr_reader :id, :description, :severity, :law_tags, :auto_fix

        @registry = []
        @registry_mutex = Mutex.new

        def self.inherited(subclass)
          @registry_mutex.synchronize { @registry << subclass }
        end

        def self.registry
          @registry_mutex.synchronize { @registry.dup }
        end

        # Laws that need constructor args (root:, agent:) override this to false.
        # Builder uses it to auto-discover zero-arg laws from the registry.
        def self.auto_build?
          true
        end

        # Whether a finding depends on more than the file's text and path: git history,
        # sibling files, another tree. Scan::FindingCache replays a pure law's findings
        # for unchanged content, so a law that reads further must say so here.
        def self.reads_beyond_file? = false

        # What a law *is*, declared once at the class level.
        #
        # Forty-two laws opened with the same constructor — `super()` and
        # five instance variables holding literals — which cross_file_analysis
        # reported as twenty-three byte-identical structures. Identity is a
        # declaration, so it reads as one, and LawDSL's generated classes say
        # the same five things through the same names.
        #
        # autofix defaults to false because a law that names no transform
        # cannot apply one, and a subclass that declares nothing gets false too.
        def self.declare(id:, description: "", severity: :warning, tags: [], autofix: false)
          @declaration = { id: id.to_s, description: description.to_s, severity:,
                           law_tags: Array(tags), auto_fix: autofix }
        end

        # Inherited, so a subclass of a declared rule keeps its parent's identity
        # until it declares its own.
        # LawDSL classes override this with the tags they declare.
        def self.dsl_tags = []

        def self.declaration
          return @declaration if defined?(@declaration) && @declaration

          superclass.respond_to?(:declaration) ? superclass.declaration : nil
        end

        def initialize
          declared = self.class.declaration
          @id = declared&.fetch(:id, nil) || self.class.name&.split("::")&.last&.downcase || "unknown"
          @description = declared ? declared[:description] : ""
          @severity = declared ? declared[:severity] : :warning
          @law_tags = declared ? declared[:law_tags] : []
          @auto_fix = declared ? declared[:auto_fix] : false
        end

        # Work a law can do for a whole walk before it reads each file; the linter laws batch their runs.
        def prefetch(_paths) = nil

        # Project the DSL declaration into the Law-facing metadata contract.
        # Generated scanner laws keep language/mode/autofix on their class because
        # they are executable wrappers rather than YAML-backed Definitions.
        def mode
          return :semantic if self.class.respond_to?(:dsl_detect_semantic) && self.class.dsl_detect_semantic
          return :structural if self.class.respond_to?(:dsl_detect_structural) && self.class.dsl_detect_structural
          :mechanical
        end

        def languages
          return [] unless self.class.respond_to?(:dsl_langs)
          Array(self.class.dsl_langs)
        end

        def autofix = auto_fix

        # Default for AST-based laws: a subclass implements check_ast and gets
        # this for free. Rules with non-AST logic override #check instead.
        def check(code, path:)
          raise NotImplementedError, "#{self.class}#check not implemented" unless respond_to?(:check_ast)

          return [] unless path.to_s.end_with?(".rb", ".rake")

          check_ast(Prism.parse(code).value, code, path:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "#{self.class}#check_ast", severity: :load_bearing, path:)
          raise "law #{@id} AST check failed: #{e.class}: #{e.message}"
        end

        def language(path)
          return "javascript" if File.basename(path).match?(/\Aface\.part\d+\.txt\z/)

          Master.language_for(path)
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

        # Every node under this law, in source order. Ten rules in
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
            next if line.match?(/scan:\s*intentional\b/)
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

      # Adapts the canonical Law::Definition contract to the scanner's
      # finding interface. This is an adapter, not a second Law declaration or
      # registry: identity, severity, scope, fixtures, and repair guidance live
      # with the canonical definition and are audited against laws.yml.
      class CanonicalLawAdapter
        attr_reader :definition

        # A canonical definition scans the text it is handed and nothing else, so
        # Fix::Scan::FindingCache may replay its findings for unchanged content.
        def self.reads_beyond_file? = false

        def initialize(definition)
          raise ArgumentError, "canonical law definition required" unless definition.respond_to?(:id)

          @definition = definition
          @id = definition.id.to_s
        end

        def id = @id
        def description = definition.ask.to_s.empty? ? definition.practice.to_s : definition.ask.to_s
        def severity = normalize_severity(definition.severity)
        def law_tags = [definition.id.to_s]
        def auto_fix = false
        def autofix = definition.autofix
        def languages = Array(definition.languages).map(&:to_s)
        def mode = definition.mode
        def prefetch(_paths) = nil

        def check(code, path:)
          return [] unless definition.enforceable? && definition.scannable?
          return [] unless definition.applies?(path.to_s, Master.language_for(path))

          stream = definition.mode.to_sym == :opportunity ? :lexical_opportunities : :lexical_violations
          definition.scan(code, file: path).map do |hit|
            Finding.build(
              law: id,
              message: "#{id}: #{definition.fix}",
              line: hit.line,
              severity:,
              fix: definition.fix,
              tags: [id, stream, definition.mode],
            )
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "CanonicalLawAdapter#check", severity: :load_bearing, path:)
          raise "canonical Law #{id} detector failed for #{path}: #{e.class}: #{e.message}"
        end

        private

        def normalize_severity(value)
          { warn: :warning, warning: :warning, info: :info, error: :error, critical: :critical, veto: :veto }.fetch(value.to_sym, value.to_sym)
        end
      end

    end
  end
end
