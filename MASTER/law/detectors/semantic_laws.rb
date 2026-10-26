# frozen_string_literal: true

module Master
  module Review
    module Scan
      module Laws
        # The Laws that call a model share how they receive one, and the
        # scanner finds them by asking whether they respond to it.
        module NeedsModel
          def set_agent(agent)
            @agent = agent
            self
          end

          def agent? = !@agent.nil?

          # The semantic tier is the only rule tier that spends money, so it is
          # the only one a provider spend limit can silently delete. Returning
          # [] on every file without recording why is what makes a run of
          # unscanned files read as a clean bill of health, so the skip is
          # named on the check before it is taken.
          OFFLINE_ERRORS_PATTERN = /missing configuration|api.?key|unauthorized|no.*provider|no.*claude.*path|no.*on.*path/i.freeze
          LANE_SILENCE_PATTERN = /\Ano lane answered \d+ calls in a row; model work is skipped for \d+ minutes\./i.freeze

          def quota_paused?
            return false unless Master::Io::QuotaCheck.blocked?

            Master::Io::QuotaCheck.skipped("semantic Laws")
            true
          end

          # A model call came back with a spend limit or a refused key. Trip
          # once for the whole tier rather than once per file: 4,663 identical
          # log entries is what this rule population produced the last time a
          # per-file failure was recorded per file.
          def note_model_failure(error)
            message = error.message.to_s
            if message.match?(LANE_SILENCE_PATTERN)
              Master::Io::QuotaCheck.skipped("semantic Laws")
              return true
            end

            # No model attached is not a provider answer, and says nothing about a key or a balance.
            return false if message.include?("no model agent configured")

            Master::Io::QuotaCheck.trip_if_limited(source: "semantic Law #{@id}", message:)
          end

          # The file is already in the prompt and the reply is a list of lines,
          # so tools only let the model wander the repo: offered them, a free
          # model spent up to eight rounds grepping per file and then failed on
          # the round cap, a third of every call during a 1,199-file scan.
          def ask_without_tools(prompt, operation:)
            previous = Fiber[:master_no_tools]
            Fiber[:master_no_tools] = true
            @agent.ask(prompt, operation:).to_s
          ensure
            Fiber[:master_no_tools] = previous
          end
        end

        # Steelman-first red-team: the model must defend the code before it can attack it.
        # This suppresses false positives by forcing consideration of legitimate reasons
        # before a violation can survive. Deep depth only; one LLM call per file.
        class AdversarialLaw < Law
          def self.reads_beyond_file? = true

          PROMPT_TEMPLATE = <<~PROMPT.freeze
          Red-team review of %<path>s.

          Step 1 — Steelman (internal, do not output): write the three strongest
          arguments that this code is correct and should not be changed.

          Step 2 — Answer each question silently; only include findings below
          if they survive the steelman:
            1. What is wrong with this design that I have not spotted?
            2. What would an attacker do with this code?
            3. What assumption is this built on that could be false?
            4. What breaks at scale or under failure?
            5. Is this wired to anything? Could it be deleted without loss?
            6. Is there a simpler approach that was not taken?
            7. What should be relocated or transformed to a different format?

          Step 3 — Output only surviving violations.
          Format: ISSUE:LINE:description (one per line).
          If nothing survives, respond with exactly: CLEAN

          Focus on: broken contracts, hidden coupling, axiom violations (CQS,
          ONE_JOB, GUARD_EXPENSIVE, FAIL_VISIBLY), security, and logic errors.
          Ignore style. Do not hallucinate method names.

          Code (%<lang>s):
          %<code>s
        PROMPT

          declare id: "adversarial", severity: :error, tags: %i[ONE_JOB CQS GUARD_EXPENSIVE FAIL_VISIBLY COMPOSABLE],
                  autofix: true, description: "Red-team scan: steelman then challenge — suppresses false positives"

          def initialize(agent: nil)
            super()
            @agent = agent
          end

          def self.auto_build? = false

          include NeedsModel

          def check(code, path:)
            return [] unless @agent
            return [] if quota_paused?
            return [] unless (lang = language(path))

            prompt = format(PROMPT_TEMPLATE, path: File.basename(path),
                                             lang:,
                                             code: code[0, 3_000])
            response = ask_without_tools(prompt, operation: :scan_adversarial)
            parse_findings(response)
          rescue StandardError => e
            # Missing credentials/capability and an exhausted provider are explicit
            # non-results. Unexpected model/parser faults are measurement failures:
            # log them and raise so FileProcessor returns a failed scan rather than
            # silently turning an unevaluated semantic tier into CLEAN.
            offline = e.message.to_s.match?(OFFLINE_ERRORS_PATTERN)
            limited = note_model_failure(e)
            if offline || limited
              detail = offline ? "provider capability/configuration unavailable" : "provider spend/quota limit reached"
              raise "semantic assessment INCONCLUSIVE: #{detail} for #{path} (#{e.class}: #{e.message})"
            end

            Master::Ground::Swallow.log(e, context: "#{self.class}#check", severity: :load_bearing, path:)
            raise
          end

          private

          def parse_findings(response)
            response_normalized = response.strip.upcase
            return [] if response_normalized.start_with?("CLEAN")

            response.lines.filter_map do |line|
              match = line.strip.match(/\AISSUE:(\d+):(.+)\z/)
              next unless match
              finding(line: match[1].to_i, message: "adversarial: #{match[2].strip}")
            end
          end
        end

        require_relative "../../lib/review/scan/finding"
        # LLM review for meaning that resists deterministic detection.
        # Each eligible file receives independent violation and opportunity
        # requests; the same law can therefore yield two distinct findings. A
        # deterministic detector remains layered evidence for that one law.
        class SemanticLaw < Law
          def self.reads_beyond_file? = true

          CODE_SNIPPET_LIMIT = 2000

          declare id: "semantic", severity: :warning, autofix: true,
                  description: "LLM-based rule review (violations + opportunities)"

          def initialize(agent: nil)
            super()
            @agent = agent
            @cache = {}
            reload_semantic_laws!
          end

          def self.auto_build? = false

          include NeedsModel

          def check(code, path:)
            lang = language(path)
            return [] unless lang
            raise "semantic assessment INCONCLUSIVE: no model agent configured for #{path}" unless @agent
            if quota_paused?
              raise "semantic assessment INCONCLUSIVE: quota check paused model assessment for #{path}"
            end

            reload_semantic_laws_if_stale
            scoped = laws_for(lang, path:)
            return [] if scoped.empty?

            base_key = semantic_cache_key(path, code)
            # Keep violation detection and improvement discovery as distinct
            # model calls, cache entries, operations, prompts and verdicts. A
            # combined CLEAN reply previously hid whether both questions ran.
            %i[violation opportunity].flat_map do |stream|
              cache_key = "#{base_key}:#{stream}"
              next @cache[cache_key] if @cache.key?(cache_key)

              operation = stream == :violation ? :scan_semantic_violations : :scan_semantic_opportunities
              response = ask_without_tools(build_prompt(code, path, scoped, mode: stream), operation:)
              @cache[cache_key] = parse_findings(response, scoped, mode: stream)
            end
          rescue StandardError => e
            offline = e.message.to_s.match?(OFFLINE_ERRORS_PATTERN)
            limited = note_model_failure(e)
            if offline || limited
              detail = offline ? "provider capability/configuration unavailable" : "provider spend/quota limit reached"
              raise "semantic assessment INCONCLUSIVE: #{detail} for #{path} (#{e.class}: #{e.message})"
            end

            Master::Ground::Swallow.log(e, context: "#{self.class}#check", severity: :load_bearing, path:)
            raise
          end

          private

          # Each axiom is { prompt:, severity:, mode: }. info-tier violations stay
          # out of the prompt — they're noise that doubles cost. info-tier
          # opportunities stay in: that's their whole point.
          def reload_semantic_laws!
            @laws = load_semantic_laws
            @law_tags = @laws.keys.map(&:to_sym)
            @laws_mtime = laws_mtime
            @prompt_frames = {}
          end

          # Thirty-seven rules declare `languages:` and nothing read it. from_yaml
          # kept prompt, severity, mode, reversibility and blast_radius and
          # dropped the rest, so this pass put a css rule in front of every file
          # in the tree. Its only reader was the lexical bridge, which carries no
          # rules at all now. Hence a frame per language: one frame built at load
          # cannot honour a scope.
          #
          # Empty means every language, as it does for Law::Law#applies? and
          # Law#applies_to?. Law refuses a language FILE_LANGUAGE_MAP never
          # produces (Law#prove!); test_semantic_rule_scope asks the same of
          # this population, because a declared language nothing emits aims a rule
          # at no file at all — which is how `rails`, `prose` and `erb` sat here.
          # Every Law is assessed against every artifact, regardless of the file's
          # implementation language. Languages are detector implementation details,
          # not exemptions from semantic or visual review.
          def laws_for(_language, path: nil)
            @laws
          end

          def path_matches?(path, pattern)
            pattern.is_a?(Regexp) ? path.match?(pattern) : path.include?(pattern.to_s)
          end

          def reload_semantic_laws_if_stale
            reload_semantic_laws! if @laws_mtime != laws_mtime
          end

          def laws_mtime
            paths = [Master::LAWS_PATH, *Dir.glob(File.join(Master::ROOT, "law", "**", "*.rb"))]
            paths.sort.filter_map do |path|
              next unless File.exist?(path)

              stat = File.stat(path)
              [path, stat.size, stat.ino, stat.mtime.to_r]
            end
          end

          def semantic_cache_key(path, code)
            require "digest"
            stat = File.stat(path) if File.file?(path)
            file_stamp = stat && [stat.size, stat.ino, stat.mtime.to_r]
            [path, file_stamp, Digest::SHA256.hexdigest(code), @laws_mtime].join(":")
          end

          # One source: semantic review is populated from executable Law definitions.
          # The YAML catalogue retains naming, provenance, scope, and other operator
          # metadata, but it no longer carries a second semantic implementation.
          def load_semantic_laws
            from_law
          end

          # The same executable law population seeds both semantic streams.
          # Laws with an authored ask keep it; deterministic-only laws use their
          # repair contract and worked examples to stay visible to semantic review.
          def from_law
            require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
            ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
            require_relative "../../lib/review/scan/law_dsl" unless defined?(Master::Review::Scan::LawDSL)

            laws = ::Law.definitions.values.select(&:enforceable?).each_with_object({}) do |law, entries|
              id = law.id.to_s.upcase
              question = law.ask.to_s.strip
              question = "Does this artifact breach #{id} or miss an improvement implied by its repair contract?" if question.empty?
              entries[id] = {
                prompt: [question, "Repair contract: #{law.fix}", "Forbidden example: #{law.bad.strip}", "Compliant example: #{law.good.strip}"].join("\\n"),
                severity: law.severity,
                mode: :both,
                reversibility: nil,
                blast_radius: nil,
                languages: [],
                path: nil,
                path_exclude: nil,
              }
            end

            # Inline Ruby detector implementations belong to the same Law
            # population. They contribute behavior, never a second policy identity.
            Master::Review::Scan::Law.registry.each do |klass|
              next unless klass.respond_to?(:dsl_id) && !klass.dsl_id.to_s.empty?

              instance = Master::Review::Scan::LawFactory.build(klass, root: Master::ROOT)
              id = instance.id.to_s.upcase
              next if laws.key?(id)

              description = instance.description.to_s.strip
              description = id.tr("_", " ").downcase if description.empty?
              laws[id] = {
                prompt: "#{description}. Evaluate the same requirement for a clear breach and for a concrete improvement.",
                severity: instance.severity,
                mode: :both,
                reversibility: nil,
                blast_radius: nil,
                languages: [],
                path: nil,
                path_exclude: nil,
              }
            end
            laws.freeze
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "SemanticLaw.from_law", severity: :load_bearing)
            raise
          end

          def build_prompt(code, path, scoped, mode:)
            heading, empty_response, instruction = case mode.to_sym
            when :violation
              ["SEMANTIC VIOLATIONS", "CLEAN",
               "Find only clear breaches of the stated laws. Do not list improvements."]
            when :opportunity
              ["SEMANTIC OPPORTUNITIES", "NONE",
               "Independently find specific improvements that better satisfy the stated laws, even when the current code is not in violation. Do not relabel existing violations as opportunities."]
            else
              raise ArgumentError, "unknown semantic assessment mode: #{mode.inspect}"
            end
            rules = scoped.map { |id, axiom| "#{id}: #{axiom[:prompt]}" }.join("\n")
            <<~PROMPT
            #{heading}: review #{File.basename(path)}.

            #{instruction}
            Return only LAW_ID:LINE:description records for the rules listed below.
            If no result exists for this stream, return exactly #{empty_response}.
            Do not return the other stream's verdict in this response.

            #{rules}

            Code (first #{CODE_SNIPPET_LIMIT} chars):
            #{code[0, CODE_SNIPPET_LIMIT]}
          PROMPT
          end

          def prompt_frame_for(scoped, language)
            @prompt_frames[language] ||= build_prompt_frame(scoped)
          end

          def build_prompt_frame(rules)
            # Each Law participates in both streams. They are separate judgements:
            # a breach does not satisfy or suppress the opportunity assessment.
            build = [violation_block(rules), opportunity_block(rules)]
            build.join("\\n\\n")
          end

          def violation_block(rules)
            list = rules.map { |id, a| "#{id}: #{a[:prompt]}" }.join("\n")
            <<~BLOCK
            VIOLATIONS — list ONLY clear breaches. Format: LAW_ID:LINE:description.
            If clean, write CLEAN on its own line.
            #{list}
          BLOCK
          end

          def opportunity_block(rules)
            list = rules.map { |id, a| "#{id}: #{a[:prompt]}" }.join("\n")
            <<~BLOCK
            OPPORTUNITIES — list refactors only if they would simplify. Format: LAW_ID:LINE:reason.
            If none, write NONE on its own line.
            #{list}
          BLOCK
          end

          # Against the rules this file was actually asked about, not against all
          # of them: a model handed a css frame that answers RAILS_VIEW_PURITY has
          # invented a rule for this file, and accepting it would put the scope
          # back where it was.
          def parse_findings(response, scoped, mode: nil)
            response.lines.filter_map do |line|
              stripped = line.strip
              next if stripped.empty? || %w[CLEAN NONE].include?(stripped.upcase)

              match = stripped.match(/\A([A-Z_][A-Z0-9_]*):(\d+):(.+)\z/)
              next unless match && scoped.key?(match[1])

              axiom = scoped[match[1]]
              Finding.build(
                law: match[1],
                message: match[3].strip,
                line: match[2].to_i,
                severity: axiom[:severity],
                fix: nil,
                tags: [
                  match[1].to_sym,
                  (mode || axiom[:mode]).to_sym == :opportunity ? :semantic_opportunities : :semantic_violations,
                  (mode || axiom[:mode]).to_sym,
                ],
                reversibility: axiom[:reversibility],
                blast_radius: axiom[:blast_radius],
              )
            end
          end
        end

        # Comments above method defs that no longer describe what the code does.
        # Lexical pass extracts (comment, method_body) pairs; LLM judges drift in one
        # batched call per file. Pairs with the "reassess on touch" directive: lying
        # comments are factual bugs, not style noise.
        class CommentDriftLaw < Law
          def self.reads_beyond_file? = true

          MAX_PAIRS_PER_FILE = 8
          # Lines of method body sent to LLM for drift comparison.
          BODY_SNIPPET = 20

          declare id: "comment_drift", severity: :warning, tags: %i[SELF_EXPLAINING EXPLICIT], autofix: true,
                  description: "Comment claim doesn't match method body — comment is lying"

          def initialize(agent: nil)
            super()
            @agent = agent
          end

          def self.auto_build? = false

          include NeedsModel

          def check(code, path:)
            return [] unless path.end_with?(".rb") && @agent
            return [] if quota_paused?
            pairs = extract_pairs(code)
            return [] if pairs.empty?
            response = @agent.ask(build_prompt(pairs, path), operation: :scan_comment_drift).to_s
            parse_findings(response, pairs)
          rescue StandardError => e
            # An absent CLI and an exhausted provider are explicit non-results.
            # A present but broken model is a measurement failure and must not
            # become a false clean scan.
            return [] if note_model_failure(e)

            if absent_capability?(e)
              return [] if @capability_absent

              @capability_absent = true
              Master::Ground::Swallow.log(e, context: "CommentDriftLaw", severity: :cosmetic, path:)
              return []
            end

            Master::Ground::Swallow.log(e, context: "CommentDriftLaw", severity: :load_bearing, path:)
            raise
          end

          # ENOENT on the CLI itself, however the runner wraps it. Not a guess at
          # the message shape: agent.rb raises with the binary name in the text,
          # and Errno::ENOENT is what actually reaches here when it is absent.
          def absent_capability?(error)
            error.is_a?(Errno::ENOENT) ||
              error.message.match?(/No such file or directory|command not found|not installed/i)
          end

          private

          def extract_pairs(code)
            lines = code.lines
            pairs = []
            i = 0
            while i < lines.size && pairs.size < MAX_PAIRS_PER_FILE
              comment_start = i
              while i < lines.size && lines[i] =~ /\A\s*#/
                i += 1
              end
              comment_lines = lines[comment_start...i]
              if comment_lines.any? && i < lines.size && lines[i] =~ /\A\s*def\s/
                comment_text = comment_lines.map { |l| l.strip.delete_prefix("#").strip }.join(" ")
                body = lines[i, BODY_SNIPPET].join
                pairs << { line: comment_start + 1, comment: comment_text, body: } unless comment_text.empty?
              end
              i += 1
            end
            pairs
          end

          def format_pair(p, idx)
            "[#{idx}] line #{p[:line]}\nCOMMENT: #{p[:comment]}\nCODE:\n#{p[:body]}"
          end

          def build_prompt(pairs, path)
            numbered = pairs.each_with_index.map { |p, idx| format_pair(p, idx) }.join("\n---\n")
            <<~PROMPT
            Audit #{File.basename(path)} for comment drift. For each numbered pair,
            decide whether the comment accurately describes what the code does.
            List ONLY indices where the comment lies or contradicts the code.
            Format each violation: INDEX:short reason (one per line)
            If all pairs are accurate, respond with exactly: CLEAN

            #{numbered}
          PROMPT
          end

          def parse_findings(response, pairs)
            return [] if response.strip.upcase == "CLEAN"
            response.lines.filter_map do |line|
              match = line.strip.match(/\A(\d+):(.+)\z/)
              next unless match
              pair_index = match[1].to_i
              pair = pairs[pair_index]
              next unless pair
              finding(line: pair[:line], message: "comment drift — #{match[2].strip}")
            end
          end
        end
      end
    end
  end
end
