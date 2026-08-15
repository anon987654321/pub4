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
        evidence_for_done_rule,
        git_commit_evidence_rule,
        council_for_done_rule,
        ideation_before_write_rule,
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
      norm = path.delete_prefix("./")
      immutable.any? { |g| g.end_with?("/") ? norm.start_with?(g) : norm == g }
    end

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
        next nil unless effect.args[:operation].to_sym == :commit
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

    def self.ruby_syntax_error(content)
      out, status = Open3.capture2e("ruby", "-c", stdin_data: content)
      status.success? ? nil : out.strip.lines.first&.strip
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
                         :safe_exec_rule, :structured_exec_rule, :evidence_for_done_rule,
                         :git_commit_evidence_rule, :council_for_done_rule,
                         :ideation_before_write_rule, :ruby_syntax_error, :safe_rx
  end
end
