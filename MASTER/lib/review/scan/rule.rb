# frozen_string_literal: true

module Master
  module Review
    module Scan
      require_relative "finding"

      class Rule
        include SourceMasking

        EXT_LANG = Master::FILE_LANGUAGE_MAP

        attr_reader :id, :description, :severity, :rule_tags, :auto_fix

        @registry = []
        @registry_mutex = Mutex.new

        def self.inherited(subclass)
          @registry_mutex.synchronize { @registry << subclass }
        end

        def self.registry
          @registry_mutex.synchronize { @registry.dup }
        end

        # Rules that need constructor args (root:, agent:) override this to false.
        # Builder uses it to auto-discover zero-arg rules from the registry.
        def self.auto_build?
          true
        end

        # What a rule *is*, declared once at the class level.
        #
        # Forty-two subclasses opened with the same constructor — `super()` and
        # five instance variables holding literals — which cross_file_analysis
        # reported as twenty-three byte-identical structures. Identity is a
        # declaration, so it reads as one, and RuleDSL's generated classes say
        # the same five things through the same names.
        #
        # autofix defaults to false because a rule that names no transform
        # cannot apply one; the base default stays true for a rule that declares
        # nothing at all, which is what an undeclared subclass has always got.
        def self.declare(id:, description: "", severity: :warning, tags: [], autofix: false)
          @declaration = { id: id.to_s, description: description.to_s, severity:,
                           rule_tags: Array(tags), auto_fix: autofix }
        end

        # Inherited, so a subclass of a declared rule keeps its parent's identity
        # until it declares its own.
        def self.declaration
          return @declaration if defined?(@declaration) && @declaration

          superclass.respond_to?(:declaration) ? superclass.declaration : nil
        end

        def initialize
          declared = self.class.declaration
          @id = declared&.fetch(:id, nil) || self.class.name&.split("::")&.last&.downcase || "unknown"
          @description = declared ? declared[:description] : ""
          @severity = declared ? declared[:severity] : :warning
          @rule_tags = declared ? declared[:rule_tags] : []
          @auto_fix = declared ? declared[:auto_fix] : true
        end

        # Default for AST-based rules: a subclass implements check_ast and gets
        # this for free. Rules with non-AST logic override #check instead.
        def check(code, path:)
          raise NotImplementedError, "#{self.class}#check not implemented" unless respond_to?(:check_ast)

          return [] unless path.to_s.end_with?(".rb", ".rake")

          check_ast(Prism.parse(code).value, code, path:)
        rescue StandardError => e
          # [] is also a clean file's answer, so only this report separates them.
          Master::Ground::Swallow.log(e, context: "#{self.class}#check_ast", severity: :load_bearing, path:)
          []
        end

        def language(path)
          return "javascript" if File.basename(path).match?(/\Aface\.part\d+\.txt\z/)
          EXT_LANG[File.extname(path).downcase]
        end

        def applies_to?(path, languages)
          return true if languages.nil? || languages.empty?
          lang = language(path)
          lang && languages.include?(lang)
        end

        protected

        def finding(line:, message:, fix: nil, confidence: nil, why: nil, genealogy: nil, impact_radius: nil, dedupe_key: nil)
          Finding.build(
            rule: @id,
            message:,
            line:,
            severity: @severity,
            fix:,
            tags: @rule_tags,
            confidence: confidence || default_confidence,
            why: why || default_why(message),
            genealogy: genealogy || default_genealogy(message),
            dedupe_key: dedupe_key || default_dedupe_key(message),
            impact_radius:,
          )
        end

        # Every node under this one, in source order. Ten rules in
        # structural_rules.rb each carried a byte-identical private `visit` doing
        # exactly this — the copy-paste TODO.md names as "one shared AST-walk
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
        # purpose: the rules that read this ask how large a def or a class is,
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
        # Rules that measure the shape of a line read it without its marker. A
        # line still too long with the marker removed is still too long.
        #
        # The marker can share its comment with other machine directives —
        # `# rubocop:disable Lint/RescueException -- scan: intentional` is one
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
          [@rule_tags.first || "GENERAL", @id, message.to_s.split(" — ").first.to_s]
        end

        def default_dedupe_key(message)
          "#{@id}:#{message.to_s.downcase.gsub(/\b\d+\b/, "#")}"
        end
      end
    end
  end
end
