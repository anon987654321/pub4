# frozen_string_literal: true

require "open3"
require "yaml"

module Master::Core
  # Constitution — the single gate. Every Effect the agent proposes folds
  # through the rules here before the World performs anything. This is where the
  # old council, scan, judge, biases, veto, evidence, sharp_edges, and the Guard
  # all live now: not as subsystems, but as rules over effects. One `admit`.
  #
  # A rule watches a verb, judges an effect against the live data/*.yml (the one
  # source), and returns Allow (pass), Revise (rewrite for the rules after it),
  # or Block (stop). admit folds them: the first Block wins; Revises carry
  # forward; what comes out the end is the effect the World will perform.
  class Constitution
    Rule = Data.define(:id, :verbs, :judge) do
      def watches?(verb) = verbs.include?(verb)
    end

    REPO_TREES = %w[MASTER RAILS OPENBSD STUDIO bin dotfiles].freeze
    FORBIDDEN_BASENAMES = %w[summary.md analysis.md report.md todo.md notes.md changelog.md].freeze
    TWO_HATS_LINES = 200
    SCOPE_TREES = 3
    SCOPE_SECONDS = 1_800
    FEAT_RX = /\b(feat|fix|add|ship|implement)\b/i
    REFACTOR_RX = /\b(refactor|cleanup|clean up|restructure|rewrite)\b/i

    # verify is the scanner, supplied rather than required: the spine reaches
    # nothing in lib/. It takes (path:, content:) and answers what the write
    # introduces, so the design law judges a write on the way in, like every
    # other rule here, instead of waiting for someone to run a scan.
    def self.load(data_dir:, verify: nil)
      rules = default_rules(YAML.safe_load_file(File.join(data_dir, "rules.yml"), aliases: true))
      rules += [scan_clean_rule(verify)] if verify
      new(rules:)
    end

    def initialize(rules:)
      @rules = rules
    end

    # Fold the effect through every applicable rule. Total: returns Allow or Block.
    def admit(effect, memory)
      @rules.each do |rule|
        next unless rule.watches?(effect.verb)

        case rule.judge.call(effect, memory)
        in Verdict::Block => b then return b
        in Verdict::Revise(effect: revised) then effect = revised
        else next
        end
      end
      Verdict::Allow.new(effect:)
    end

    # The rules. Each is a few lines because the dangerous thing is expressed as
    # a predicate, not prose. Safety rules Block; hygiene rules Revise.
    def self.default_rules(data)
      veto = (data["veto_patterns"] || {}).filter_map { |n, s| [n, safe_rx(s["detect"])] }.to_h
      immutable = Array(data.dig("paths", "immutable")).map(&:to_s).freeze

      [
        no_secret_rule(veto),
        immutable_paths_rule(immutable),
        ruby_parses_rule,
        structured_exec_rule,
        safe_exec_rule(veto),
        batch_delete_rule,
        forbidden_file_rule,
        scope_creep_rule,
        evidence_for_done_rule,
        git_commit_evidence_rule,
        two_hats_rule,
        council_for_done_rule,
        ideation_before_write_rule,
        new_path_rule,
      ]
    end

    # The agent may not rewrite the constitution it is judged by or the spine
    # that folds its effects. A write, or a git stage of such a path, is blocked.
    def self.immutable_paths_rule(immutable)
      Rule.new(id: :immutable_paths, verbs: %i[write git], judge: lambda { |effect, _memory|
        targets = effect.verb == :write ? [effect.args[:path]] : Array(effect.args[:paths])
        hit = targets.compact.map(&:to_s).find { |path| immutable_hit?(path, immutable) }
        next nil unless hit

        Verdict::Block.new(reason: "immutable path: #{hit}", by: :immutable_paths)
      })
    end

    # Prefix match against the immutable list; a trailing "/" entry guards a
    # whole subtree, a bare entry guards that exact path.
    def self.immutable_hit?(path, immutable)
      # Lexical match used to miss data/./soul.yml and data/foo/../soul.yml
      # while World#within expands those to the real file and writes it.
      norm = expand_guard_path(path)
      immutable.any? do |guard|
        target = expand_guard_path(guard)
        if guard.to_s.end_with?("/")
          norm == target || norm.start_with?("#{target}/")
        else
          norm == target
        end
      end
    end

    def self.expand_guard_path(path)
      File.expand_path(path.to_s.delete_prefix("./"), "/")
    end
    private_class_method :expand_guard_path

    # No credential ever reaches disk or the transcript.
    def self.no_secret_rule(veto)
      Rule.new(id: :no_secret, verbs: %i[write note], judge: lambda { |effect, _memory|
        body = [effect.args[:content], effect.args[:text]].compact.map(&:to_s).join("\n")
        next nil unless veto["secrets"] && body.match?(veto["secrets"])

        Verdict::Block.new(reason: "secret in content", by: :no_secret)
      })
    end

    # Every Ruby file the agent writes must parse. The check that was missing
    # while 109 lib files rotted; here it cannot be skipped.
    def self.ruby_parses_rule
      Rule.new(id: :ruby_parses, verbs: %i[write], judge: lambda { |effect, _memory|
        next nil unless effect.args[:path].to_s.end_with?(".rb")

        err = ruby_syntax_error(effect.args[:content].to_s)
        err ? Verdict::Block.new(reason: err, by: :ruby_parses) : nil
      })
    end

    # A write may carry the debt already in the file it replaces; it may not add
    # to it. Blocking on the whole file would refuse the first repair of any file
    # that already breaks a rule.
    def self.scan_clean_rule(verify)
      Rule.new(id: :scan_clean, verbs: %i[write], judge: lambda { |effect, _memory|
        blocking = verify.call(path: effect.args[:path], content: effect.args[:content].to_s)
        next nil if blocking.empty?

        Verdict::Block.new(reason: "write introduces #{blocking.join("; ")}", by: :scan_clean)
      })
    end

    # Unsafe shell never executes.
    def self.safe_exec_rule(veto)
      Rule.new(id: :safe_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        command = Array(effect.args[:argv]).join(" ")
        next nil unless veto["unsafe_calls"] && command.match?(veto["unsafe_calls"])

        Verdict::Block.new(reason: "unsafe command", by: :safe_exec)
      })
    end

    # One path at a time. Added after a 16-file untracked wipe; the operator
    # sentence is the Fold's next exec, not a batch argv.
    def self.batch_delete_reason(argv)
      argv = Array(argv).map(&:to_s)
      return "batch delete refused: git clean without a pathspec" if git_clean_all?(argv)

      paths = delete_operands(argv)
      return if paths.size <= 1

      "batch delete refused: #{paths.size} paths — one path at a time"
    end

    def self.batch_delete_rule
      Rule.new(id: :batch_delete, verbs: %i[exec], judge: lambda { |effect, _memory|
        reason = batch_delete_reason(effect.args[:argv])
        reason ? Verdict::Block.new(reason:, by: :batch_delete) : nil
      })
    end

    def self.forbidden_file_reason(path)
      name = File.basename(path.to_s).downcase
      return unless FORBIDDEN_BASENAMES.include?(name)

      "forbidden file: #{name} — deliver code, not a sidecar markdown"
    end

    def self.forbidden_file_rule
      Rule.new(id: :forbidden_file, verbs: %i[write], judge: lambda { |effect, _memory|
        reason = forbidden_file_reason(effect.args[:path])
        reason ? Verdict::Block.new(reason:, by: :forbidden_file) : nil
      })
    end

    def self.scope_creep_reason(path, proof)
      tree = path.to_s.split("/").find { |part| REPO_TREES.include?(part) }
      trees = Array(proof.scope[:trees]) | [tree].compact
      return "scope creep: #{trees.size} trees (#{trees.join(", ")})" if trees.size >= SCOPE_TREES

      elapsed = proof.scope[:elapsed_s].to_f
      return unless elapsed >= SCOPE_SECONDS && tree && proof.scope[:trees].any? && !proof.scope[:trees].include?(tree)

      "scope creep: #{(elapsed / 60).to_i} min tangent into #{tree}"
    end

    def self.scope_creep_rule
      Rule.new(id: :scope_creep, verbs: %i[write], judge: lambda { |effect, memory|
        reason = scope_creep_reason(effect.args[:path], memory.proof)
        reason ? Verdict::Block.new(reason:, by: :scope_creep) : nil
      })
    end

    def self.two_hats_reason(message, lines)
      return if lines.to_i <= TWO_HATS_LINES

      text = message.to_s
      return unless text.match?(FEAT_RX) && text.match?(REFACTOR_RX)

      "two hats: #{lines} lines mix a feature/fix with a refactor"
    end

    def self.two_hats_rule
      Rule.new(id: :two_hats, verbs: %i[git], judge: lambda { |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit

        reason = two_hats_reason(effect.args[:message], memory.proof.scope[:write_lines])
        reason ? Verdict::Block.new(reason:, by: :two_hats) : nil
      })
    end

    def self.git_clean_all?(argv)
      File.basename(argv[0].to_s) == "git" && argv[1] == "clean" &&
        operands_after_flags(argv.drop(2)).empty?
    end

    def self.delete_operands(argv)
      return [] if argv.empty?

      cmd = File.basename(argv.first)
      rest = argv.drop(1)
      case cmd
      when "rm"
        operands_after_flags(rest)
      when "git"
        return [] unless rest[0] == "rm"

        operands_after_flags(rest.drop(1))
      else
        []
      end
    end

    def self.operands_after_flags(args)
      past = false
      args.reject do |arg|
        next false if past
        if arg == "--"
          past = true
          next true
        end
        arg.start_with?("-")
      end
    end

    def self.structured_exec_rule
      Rule.new(id: :structured_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        argv = effect.args[:argv]
        next nil if argv.is_a?(Array) && argv.all? { |arg| arg.is_a?(String) } && !argv.empty?

        Verdict::Block.new(reason: "exec requires argv: [String, ...]", by: :structured_exec)
      })
    end

    # The agent may not declare success without evidence (no completion theater).
    def self.evidence_for_done_rule
      Rule.new(id: :evidence_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil if memory.proof.proved?

        Verdict::Block.new(reason: "no passing evidence on record", by: :evidence_for_done)
      })
    end

    def self.git_commit_evidence_rule
      Rule.new(id: :git_commit_evidence, verbs: %i[git], judge: lambda { |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit
        next nil if memory.proof.proved?

        Verdict::Block.new(reason: "cannot commit before evidence threshold", by: :git_commit_evidence)
      })
    end

    # High-risk goals require an in-process council critique before done.
    def self.council_for_done_rule
      Rule.new(id: :council_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil unless memory.proof.council_required?
        next nil if memory.proof.council_cleared?

        Verdict::Block.new(reason: "run critique (council tribunal) before done on high-risk goals", by: :council_for_done)
      })
    end

    # Medium+ goals must carry ideation notes seeded before the first write.
    def self.ideation_before_write_rule
      Rule.new(id: :ideation_before_write, verbs: %i[write], judge: lambda { |_effect, memory|
        next nil if memory.proof.ideation_satisfied?

        Verdict::Block.new(reason: "ideation not complete — approaches/chosen must be in memory", by: :ideation_before_write)
      })
    end

    # Medium+ unread path: read it first (edit) or ask (new file). The January
    # delete-and-recreate incident wrote over approved work without a read.
    def self.new_path_reason(path, proof)
      return unless %i[medium high critical].include?(proof.risk)
      return if Array(proof.scope[:read_paths]).include?(path.to_s)
      return if proof.scope[:asked]

      "unread path #{path} — read it or ask before writing"
    end

    def self.new_path_rule
      Rule.new(id: :new_path_ask, verbs: %i[write], judge: lambda { |effect, memory|
        reason = new_path_reason(effect.args[:path], memory.proof)
        reason ? Verdict::Block.new(reason:, by: :new_path_ask) : nil
      })
    end

    # The fold blocks on this answer before it admits a write, so a parser that
    # does not return holds up every write. join returns nil on timeout rather
    # than raising, which is where the child gets killed.
    SYNTAX_CHECK_TIMEOUT_S = 5

    def self.ruby_syntax_error(content)
      Open3.popen2e("ruby", "-c") do |stdin, out, wait_thr|
        stdin.write(content)
        stdin.close
        unless wait_thr.join(SYNTAX_CHECK_TIMEOUT_S)
          Process.kill("KILL", wait_thr.pid)
          next "syntax check exceeded #{SYNTAX_CHECK_TIMEOUT_S}s"
        end

        wait_thr.value.success? ? nil : out.read.strip.lines.first&.strip
      end
    end

    def self.safe_rx(pattern)
      Regexp.new(pattern, Regexp::MULTILINE)
    rescue RegexpError
      nil
    end

    # The surface is load, admit, and immutable_paths_rule — which
    # test/core/test_immutable_paths.rb builds directly. The rest are rule
    # factories `default_rules` calls and nothing else does, verified against
    # lib/, test/, spec/, tools/, bin/ and web/.
    #
    # Declared rather than merely true: `private` marks a position in the
    # instance-method stream and class methods never enter it, so this class read
    # as 16 public methods under ABSTRACTION no matter how it was arranged. That
    # is the idiom being measured, not the surface — see DEBT.md, "The fold spine
    # had never been scanned". Unlike Memory, this class did not need splitting:
    # its count was the idiom, and Memory's was the design.
    private_class_method :default_rules, :immutable_hit?, :no_secret_rule, :ruby_parses_rule, :scan_clean_rule,
                         :safe_exec_rule, :structured_exec_rule, :batch_delete_rule, :delete_operands,
                         :operands_after_flags, :git_clean_all?, :forbidden_file_rule, :scope_creep_rule,
                         :two_hats_rule, :evidence_for_done_rule,
                         :git_commit_evidence_rule, :council_for_done_rule,
                         :ideation_before_write_rule, :new_path_rule, :ruby_syntax_error, :safe_rx
  end
end
