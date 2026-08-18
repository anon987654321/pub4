# frozen_string_literal: true

module Master::Core
  module ConstitutionRules
    def self.build_rules(data, verify: nil)
      veto = (data["veto_patterns"] || {}).filter_map { |n, s| [n, safe_rx(s["detect"])] }.to_h
      immutable = Array(data.dig("paths", "immutable")).map(&:to_s).freeze

      rules = [
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
      rules << scan_clean_rule(verify) if verify
      rules
    end

    def self.immutable_paths_rule(immutable)
      Constitution::Rule.new(id: :immutable_paths, verbs: %i[write git], judge: lambda { |effect, _memory|
        targets = effect.verb == :write ? [effect.args[:path]] : Array(effect.args[:paths])
        hit = targets.compact.map(&:to_s).find { |path| immutable_hit?(path, immutable) }
        next nil unless hit

        Verdict::Block.new(reason: "immutable path: #{hit}", by: :immutable_paths)
      })
    end

    def self.immutable_hit?(path, immutable)
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

    def self.no_secret_rule(veto)
      Constitution::Rule.new(id: :no_secret, verbs: %i[write note], judge: lambda { |effect, _memory|
        body = [effect.args[:content], effect.args[:text]].compact.map(&:to_s).join("\n")
        next nil unless veto["secrets"] && body.match?(veto["secrets"])

        Verdict::Block.new(reason: "secret in content", by: :no_secret)
      })
    end

    def self.ruby_parses_rule
      Constitution::Rule.new(id: :ruby_parses, verbs: %i[write], judge: lambda { |effect, _memory|
        next nil unless effect.args[:path].to_s.end_with?(".rb")

        err = ruby_syntax_error(effect.args[:content].to_s)
        err ? Verdict::Block.new(reason: err, by: :ruby_parses) : nil
      })
    end

    def self.scan_clean_rule(verify)
      Constitution::Rule.new(id: :scan_clean, verbs: %i[write], judge: lambda { |effect, _memory|
        result = verify.call(path: effect.args[:path].to_s, content: effect.args[:content].to_s)
        result.ok? ? nil : Verdict::Revise.new(effect:)
      })
    end

    def self.safe_exec_rule(veto)
      Constitution::Rule.new(id: :safe_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        cmd = Array(effect.args[:command]).map(&:to_s).join(" ")
        next nil unless veto["exec"] && cmd.match?(veto["exec"])

        Verdict::Block.new(reason: "exec pattern blocked", by: :safe_exec)
      })
    end

    def self.batch_delete_rule
      Constitution::Rule.new(id: :batch_delete, verbs: %i[git], judge: lambda { |effect, _memory|
        reason = batch_delete_reason(effect.args[:argv]) if effect.args[:operation].to_s.to_sym == :batch_delete
        reason ? Verdict::Block.new(reason:, by: :batch_delete) : nil
      })
    end

    def self.batch_delete_reason(argv)
      return unless argv.grep_v(/^-/).size > 10

      "batch delete > 10 files requires explicit approval"
    end

    def self.forbidden_file_rule
      Constitution::Rule.new(id: :forbidden_paths, verbs: %i[write], judge: lambda { |effect, _memory|
        reason = forbidden_file_reason(effect.args[:path])
        reason ? Verdict::Block.new(reason:, by: :forbidden_paths) : nil
      })
    end

    def self.forbidden_file_reason(path)
      Constitution::FORBIDDEN_BASENAMES.each do |basename|
        return "forbidden: #{path} — commit history instead" if File.basename(path.to_s) == basename
      end
      nil
    end

    def self.scope_creep_rule
      Constitution::Rule.new(id: :scope_creep, verbs: %i[write], judge: lambda { |effect, memory|
        reason = scope_creep_reason(effect.args[:path], memory.proof)
        reason ? Verdict::Block.new(reason:, by: :scope_creep) : nil
      })
    end

    def self.scope_creep_reason(path, proof)
      return unless proof.risk.to_s =~ /medium|high|critical/i

      touched = proof.scope[:touched_trees]&.size || 0
      return "touched #{touched} trees, scope:#{Constitution::SCOPE_TREES}" if touched > Constitution::SCOPE_TREES

      touched_time = Time.now - (proof.scope[:started_at] || Time.now)
      hours = (touched_time / 3600).to_i
      return "scope time #{hours}h exceeded scope:#{Constitution::SCOPE_SECONDS / 3600}h" if touched_time > Constitution::SCOPE_SECONDS

      nil
    end

    def self.two_hats_rule
      Constitution::Rule.new(id: :two_hats, verbs: %i[write], judge: lambda { |_effect, memory|
        reason = two_hats_reason(memory.proof.message.to_s, memory.proof.scope[:lines_written].to_i)
        reason ? Verdict::Block.new(reason:, by: :two_hats) : nil
      })
    end

    def self.two_hats_reason(message, lines)
      feat_match = message.match?(Constitution::FEAT_RX)
      refactor_match = message.match?(Constitution::REFACTOR_RX)
      return if feat_match == refactor_match

      "separate feature work from refactoring (feat + refactor in one session)"
    end

    def self.structured_exec_rule
      Constitution::Rule.new(id: :structured_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        argv = effect.args[:argv]
        return nil if argv.is_a?(Array)

        Verdict::Block.new(reason: "exec args must be an array, not #{argv.class}", by: :structured_exec)
      })
    end

    def self.evidence_for_done_rule
      Constitution::Rule.new(id: :evidence_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil if memory.proof.proved?

        Verdict::Block.new(reason: "no passing evidence on record", by: :evidence_for_done)
      })
    end

    def self.git_commit_evidence_rule
      Constitution::Rule.new(id: :git_commit_evidence, verbs: %i[git], judge: lambda { |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit
        next nil if memory.proof.proved?

        Verdict::Block.new(reason: "cannot commit before evidence threshold", by: :git_commit_evidence)
      })
    end

    def self.council_for_done_rule
      Constitution::Rule.new(id: :council_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil unless memory.proof.council_required?
        next nil if memory.proof.council_cleared?

        Verdict::Block.new(reason: "run critique (council tribunal) before done on high-risk goals", by: :council_for_done)
      })
    end

    def self.ideation_before_write_rule
      Constitution::Rule.new(id: :ideation_before_write, verbs: %i[write], judge: lambda { |_effect, memory|
        next nil if memory.proof.ideation_satisfied?

        Verdict::Block.new(reason: "ideation not complete — approaches/chosen must be in memory", by: :ideation_before_write)
      })
    end

    def self.new_path_reason(path, proof)
      return unless %i[medium high critical].include?(proof.risk)
      return if Array(proof.scope[:read_paths]).include?(path.to_s)
      return if proof.scope[:asked]

      "unread path #{path} — read it or ask before writing"
    end

    def self.new_path_rule
      Constitution::Rule.new(id: :new_path_ask, verbs: %i[write], judge: lambda { |effect, memory|
        reason = new_path_reason(effect.args[:path], memory.proof)
        reason ? Verdict::Block.new(reason:, by: :new_path_ask) : nil
      })
    end

    def self.ruby_syntax_error(content)
      require "open3"
      Open3.popen2e("ruby", "-c") do |stdin, out, wait_thr|
        stdin.write(content)
        stdin.close
        unless wait_thr.join(Constitution::SYNTAX_CHECK_TIMEOUT_S)
          Process.kill("KILL", wait_thr.pid)
          next "syntax check exceeded #{Constitution::SYNTAX_CHECK_TIMEOUT_S}s"
        end

        wait_thr.value.success? ? nil : out.read.strip.lines.first&.strip
      end
    end

    def self.safe_rx(pattern)
      Regexp.new(pattern, Regexp::MULTILINE)
    rescue RegexpError
      nil
    end
  end
end
