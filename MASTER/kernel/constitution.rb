# frozen_string_literal: true

require "open3"
require "yaml"

module Master::Kernel
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

    def self.load(data_dir:)
      new(rules: default_rules(YAML.safe_load_file(File.join(data_dir, "rules.yml"), aliases: true)))
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

      [
        no_secret_rule(veto),
        ruby_parses_rule,
        structured_exec_rule,
        safe_exec_rule(veto),
        evidence_for_done_rule,
        git_commit_evidence_rule
      ]
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
        next nil if memory.proved?

        Verdict::Block.new(reason: "no passing evidence on record", by: :evidence_for_done)
      })
    end

    def self.git_commit_evidence_rule
      Rule.new(id: :git_commit_evidence, verbs: %i[git], judge: lambda { |effect, memory|
        next nil unless effect.args[:operation].to_sym == :commit
        next nil if memory.proved?

        Verdict::Block.new(reason: "cannot commit before evidence threshold", by: :git_commit_evidence)
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
  end
end
