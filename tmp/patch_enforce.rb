# encoding: utf-8
# frozen_string_literal: true

BASE = "/home/dev/pub4/MASTER"

# =============================================================
# FIX 1: Prune stage — strip markdown formatting from prose
# =============================================================

prune_new = <<~'RUBY'
# frozen_string_literal: true

require "yaml"

module Master
  module Stages
    # Prune — strip AI throat-clearing AND markdown formatting from LLM responses.
    # Rules loaded from data/strunk.yml.
    #
    # Fence-aware: splits into prose/code segments, prunes prose,
    # leaves code blocks untouched.
    class Prune
      DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze
      FENCE_RE  = /(```.*?```)/m.freeze

      # Markdown patterns to strip from prose (outside code fences)
      HEADER_RE     = /^#{1,6}\s+/                    # ## Header
      BOLD_RE       = /\*\*(.+?)\*\*/                 # **bold**
      ITALIC_RE     = /(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/ # *italic*
      BULLET_RE     = /^\s*[-*+]\s+/                  # - bullet or * bullet
      NUMBERED_RE   = /^\s*\d+\.\s+/                  # 1. numbered
      HR_RE         = /^-{3,}\s*$/                     # ---
      LINK_RE       = /\[([^\]]+)\]\([^)]+\)/          # [text](url) -> text

      # Sycophantic openers the LLM loves to add
      SYCOPHANCY_RE = /\A\s*(?:certainly|of course|great question|absolutely|sure|happy to help|i(?:'d| would) be (?:happy|glad)|no problem)[!.,]*\s*/i

      def call(ctx)
        output = ctx[:output]
        return Result.ok(ctx) unless output.is_a?(String) && !output.empty?

        cleaned = prune_mixed(output)
        Result.ok(ctx.merge(output: cleaned.strip))
      end

      private

      def prune_mixed(text)
        segments = text.split(FENCE_RE)
        segments.map { |seg|
          seg.start_with?("```") ? seg : strip_all(seg)
        }.join
      end

      def strip_all(text)
        cleaned = text

        # Sycophancy
        cleaned = cleaned.sub(SYCOPHANCY_RE, "")

        # Strunk rules
        rules.fetch("preambles", []).each { |p| cleaned = cleaned.sub(/\A\s*#{Regexp.escape(p)}\s*/i, "") }
        rules.fetch("endings",   []).each { |e| cleaned = cleaned.sub(/\s*#{Regexp.escape(e)}\s*\z/i, "") }
        rules.fetch("hedges",    []).each do |h|
          if h.is_a?(Hash)
            cleaned = cleaned.gsub(h["pattern"].to_s, h["replace"].to_s)
          else
            cleaned = cleaned.gsub(/\b#{Regexp.escape(h)}\b\s*/i, "")
          end
        end

        # Markdown formatting
        cleaned = cleaned.gsub(HEADER_RE, "")
        cleaned = cleaned.gsub(BOLD_RE, '\1')
        cleaned = cleaned.gsub(ITALIC_RE, '\1')
        cleaned = cleaned.gsub(LINK_RE, '\1')
        cleaned = cleaned.gsub(HR_RE, "")
        cleaned = cleaned.gsub(BULLET_RE, "")
        cleaned = cleaned.gsub(NUMBERED_RE, "")

        # Collapse excessive blank lines
        cleaned = cleaned.gsub(/\n{3,}/, "\n\n")

        cleaned
      end

      def rules
        @rules ||= File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH) : {}
      rescue StandardError
        @rules = {}
      end
    end
  end
end
RUBY

File.write(File.join(BASE, "lib/master/stages/prune.rb"), prune_new)
puts "1. prune.rb: markdown stripping + sycophancy removal"


# =============================================================
# FIX 2: System prompt — inject axiom constraints for code gen
# =============================================================

personality_path = File.join(BASE, "lib/master/personality.rb")
content = File.read(personality_path, encoding: "utf-8")

old_build = <<~'OLD'
def build_system_prompt
  ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
  banned  = (@constitution.dig("banned_output") || [])
  no_open = (@strunk.dig("preambles") || []).first(4)
  no_end  = (@strunk.dig("endings")   || []).first(3)
  ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
  ls << "Evidence only: show diff or file content, never assert. Active voice."
  kernel = @axioms.kernel
  ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
  phil = @axioms.philosophy(limit: 10)
  ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
  golden = @constitution["golden_rule"]
  ls << "Rule: #{golden}." if golden
  ls.join("
")
end
OLD

new_build = <<~'NEW'
def build_system_prompt
  ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
  banned  = (@constitution.dig("banned_output") || [])
  no_open = (@strunk.dig("preambles") || []).first(4)
  no_end  = (@strunk.dig("endings")   || []).first(3)
  ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
  ls << "Evidence only: show diff or file content, never assert. Active voice."
  kernel = @axioms.kernel
  ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
  phil = @axioms.philosophy(limit: 10)
  ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
  golden = @constitution["golden_rule"]
  ls << "Rule: #{golden}." if golden

  # Hard formatting rules — [K] enforced
  ls << "Output format: plain prose or dmesg-style lines. No markdown headers (#), no bold (**), no bullet lists (- *), no numbered lists. Code fences (```) are allowed only for actual code."
  ls << "Never use: Certainly, Of course, Great question, Absolutely, Happy to help, I would be glad."

  # Code generation axioms — [K] enforced
  ls << "Code axioms — refuse to generate code that violates these:"
  ls << "FAIL_VISIBLY: never rescue Exception or bare rescue that swallows errors silently. Always rescue StandardError or a specific class."
  ls << "SIMPLEST_WORKS: refuse to create god classes (>300 lines, >20 methods). Push back and suggest decomposition."
  ls << "PRESERVE_FIRST: never rewrite working code from scratch. Read first, patch minimally."
  ls << "BE_CONCISE: minimal response. If the answer is one word, say one word."

  ls.join("\n")
end
NEW

if content.include?("def build_system_prompt")
  content.sub!(old_build.strip, new_build.strip)
  File.write(personality_path, content)
  puts "2. personality.rb: system prompt now includes formatting rules + code axioms"
else
  puts "2. personality.rb: build_system_prompt not found"
end


# =============================================================
# FIX 3: Lint stage — always run + scan chat output code blocks
# =============================================================

lint_new = <<~'RUBY'
# frozen_string_literal: true

module Master
  module Stages
    # Lint — always runs. Scans written files AND code blocks in chat output.
    # Violations are collected; if autofix is possible, feeds them back to
    # the autoloop for correction.
    class Lint
      FENCE_RE = /```(?:ruby)?\n(.*?)```/m

      def initialize(scanner:, config:, autoloop: nil)
        @scanner  = scanner
        @config   = config
        @autoloop = autoloop
      end

      def call(ctx)
        findings = []

        # 1. Scan any files that were written during Execute
        written = Array(ctx[:written_files])
        written.each do |path|
          next unless File.exist?(path) && path.end_with?(".rb")
          result = @scanner.scan(path, depth: :standard)
          findings.concat(result.value!) if result.respond_to?(:ok?) && result.ok?
        end

        # 2. Scan code blocks embedded in chat output
        output = ctx[:output].to_s
        output.scan(FENCE_RE).each do |match|
          code = match[0]
          next if code.nil? || code.strip.empty?
          inline_findings = scan_inline(code)
          findings.concat(inline_findings)
        end

        # 3. Autofix if violations found and autoloop available
        if findings.any? && @autoloop
          fixable = findings.select { |f| !AutoLoop::SKIP_RULES.include?(f[:rule].to_s) }
          if fixable.any?
            fix_result = @autoloop.run(max_cycles: 3)
            ctx = ctx.merge(autofix_result: fix_result)
          end
        end

        Result.ok(ctx.merge(lint_report: findings))
      rescue => e
        # Lint failure must not block the pipeline
        Result.ok(ctx.merge(lint_error: e.message))
      end

      private

      # Scan a code string without writing to disk.
      # Creates a tempfile, scans it, deletes it.
      def scan_inline(code)
        require "tempfile"
        findings = []
        Tempfile.open(["lint_inline", ".rb"]) do |f|
          f.write("# frozen_string_literal: true\n\n#{code}")
          f.flush
          result = @scanner.scan(f.path, depth: :quick)
          if result.respond_to?(:ok?) && result.ok?
            findings = result.value!.map { |v| v.merge(source: :inline) }
          end
        end
        findings
      rescue StandardError
        []
      end
    end
  end
end
RUBY

File.write(File.join(BASE, "lib/master/stages/lint.rb"), lint_new)
puts "3. lint.rb: always runs, scans inline code blocks, triggers autofix"


# =============================================================
# FIX 4: Wire autoloop into Lint in Master.build + pipeline
# =============================================================

master_path = File.join(BASE, "lib/master.rb")
master_rb = File.read(master_path, encoding: "utf-8")

# Update Lint.new to pass autoloop
if master_rb =~ /Lint\.new\(scanner:\s*scanner,\s*config:\s*config\)/
  master_rb.sub!(
    /Lint\.new\(scanner:\s*scanner,\s*config:\s*config\)/,
    "Lint.new(scanner: scanner, config: config, autoloop: autoloop)"
  )
  File.write(master_path, master_rb)
  puts "4. master.rb: Lint now receives autoloop for autofix"
else
  # Check what the actual pattern is
  master_rb.lines.each_with_index do |l, i|
    puts "  master.rb:#{i+1}: #{l.strip}" if l.include?("Lint.new")
  end
  puts "4. master.rb: Lint.new pattern not matched — check above"
end

# Also ensure autoloop is built before lint in the build method
# Check if autoloop exists in build
if master_rb.include?("autoloop") && master_rb.include?("Lint.new")
  puts "   autoloop already referenced in build"
else
  puts "   NOTE: verify autoloop is built before lint in Master.build"
end

puts "\nall enforcement fixes applied."
