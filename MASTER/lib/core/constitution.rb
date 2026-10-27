# frozen_string_literal: true

require "prism"
require "yaml"

module Master::Core
  # Constitution — the single check. Every Effect the agent proposes folds
  # through the rules here before the World performs anything. This is where the
  # old council, scan, judge, biases, veto, evidence, sharp_edges, and the Guard
  # all live now: not as subsystems, but as rules over effects. One `admit`.
  #
  # A rule watches a verb and returns no finding, Revise, Block, or Request.
  # admit runs the full applicable chain before honoring requests: any Block
  # wins, and revisions after a pending request fail closed and require re-admission.
  class Constitution
    Law = Data.define(:id, :verbs, :judge) do
      def watches?(verb) = verbs.include?(verb)
    end

    REPO_TREES = MasterPaths::TREES
    FORBIDDEN_BASENAMES = %w[summary.md analysis.md report.md todo.md notes.md changelog.md].freeze
    TWO_HATS_LINES = 200
    SCOPE_TREES = 4
    SCOPE_SECONDS = 1_800
    FEAT_RX = /\b(feat|fix|add|ship|implement)\b/i
    REFACTOR_RX = /\b(refactor|cleanup|clean up|restructure|rewrite)\b/i

    # verify is the scanner, supplied rather than required: the spine reaches
    # nothing in lib/. It takes (path:, content:) and answers what the write
    # introduces, so the design law judges a write on the way in, like every
    # other rule here, instead of waiting for someone to run a scan.
    # sandbox is the exec counterpart of verify, and injected for the same reason:
    # the spine reaches nothing in lib/, so the hardened shell policy is handed in
    # rather than required. It takes (argv) and answers a deny reason or nil.
    #
    # Without it, the only thing standing between the model and the machine was
    # safe_exec_rule's veto regex over the joined argv. Io::Shell has consulted
    # Ground::Policy::Sandbox — an adversarial corpus covering dangerous rm in any
    # flag order, fork bombs, curl-piped-to-shell, device truncation — since that
    # check was wired in, but the Fold does not exec through Io::Shell. It execs
    # through World. So the hardened check was live for the tool path and absent
    # from the constitutional one, which is the path that actually runs unattended.
    def self.load(data_dir:, workspace_root: nil, verify: nil, sandbox: nil, capabilities: Capabilities.for(:fix))
      rules_data = YAML.safe_load_file(File.join(data_dir, "laws.yml"), aliases: true)
      master_root = File.expand_path(File.dirname(data_dir))
      workspace_root = File.expand_path(workspace_root || master_root)
      sacred_paths = Paths.sacred_paths(root: master_root)
      rules = default_rules(rules_data, sacred_paths:, master_root:, workspace_root:)
      rules += [scan_clean_rule(verify)] if verify
      rules += [sandboxed_exec_rule(sandbox)] if sandbox
      new(laws: rules, capabilities:)
    end

    def initialize(laws:, capabilities: Capabilities.for(:fix))
      @laws = laws
      @capabilities = capabilities
    end

    attr_reader :capabilities

    # Run every applicable law before returning Allow, Block, or deferred Request.
    def admit(effect, memory)
      allowed = begin
        @capabilities.allow?(effect.capability)
      rescue StandardError => e
        return Verdict::Block.new(
          reason: "capability evaluation failed: #{e.class}",
          by: :capability_evaluator_error,
        )
      end
      unless allowed == true
        return Verdict::Block.new(
          reason: "capability refused: #{effect.capability}",
          by: :capability,
        )
      end

      requests = []
      @laws.each do |law|
        watching = begin
          law.watches?(effect.verb)
        rescue StandardError => e
          return Verdict::Block.new(
            reason: "law applicability check failed: #{law.id} (#{e.class})",
            by: :law_evaluator_error,
          )
        end
        unless watching == true || watching == false
          return Verdict::Block.new(
            reason: "law applicability check returned invalid result: #{law.id} (#{watching.class})",
            by: :law_evaluator_error,
          )
        end
        next unless watching

        answer = begin
          law.judge.call(effect, memory)
        rescue StandardError => e
          return Verdict::Block.new(
            reason: "law evaluation failed: #{law.id} (#{e.class})",
            by: :law_evaluator_error,
          )
        end

        case answer
        in Verdict::Block => b then return b
        # A request is not a safety verdict. Keep checking every later law so a
        # yes cannot approve an effect that a subsequent law would block.
        in Verdict::Request => request
          unless request.effect == effect
            return Verdict::Block.new(
              reason: "law changed the effect while requesting approval",
              by: :law_evaluator_error,
            )
          end
          requests << request
        in Verdict::Revise(effect: revised)
          if requests.any?
            return Verdict::Block.new(
              reason: "effect revised after an approval request; re-admission is required",
              by: :law_order,
            )
          end
          effect = revised
        else
          # nil is the established "no finding" value for individual predicates.
          # Any other unrecognized return is a broken evaluator, not approval.
          next if answer.nil?

          return Verdict::Block.new(
            reason: "law evaluator returned invalid verdict: #{law.id} (#{answer.class})",
            by: :law_evaluator_error,
          )
        end
      end
      return Verdict::Allow.new(effect:) if requests.empty?

      if requests.one?
        request = requests.first
        return Verdict::Request.new(effect:, prompt: request.prompt, reason: request.reason, by: request.by)
      end

      prompts = requests.map { |request| "#{request.by}: #{request.prompt}" }.join("\n")
      reasons = requests.map { |request| "#{request.by}: #{request.reason}" }.join("; ")
      Verdict::Request.new(
        effect:,
        prompt: "This effect needs approval for all checks:\n#{prompts}",
        reason: reasons,
        by: :multiple_constitutional_checks,
      )
    end

    # The rules. Each is a few lines because the dangerous thing is expressed as
    # a predicate, not prose. Safety rules Block; hygiene rules Revise.
    def self.default_rules(data, sacred_paths: [], master_root: nil, workspace_root: nil)
      veto = (data["veto_patterns"] || {}).to_h { |n, s| [n, safe_rx(n, s["detect"])] }
      immutable = Array(sacred_paths).map(&:to_s).freeze

      [
        no_secret_rule(veto),
        immutable_paths_rule(immutable, master_root:, workspace_root:),
        configuration_invariant_rule(workspace_root:),
        ruby_parses_rule,
        structured_exec_rule,
        safe_exec_rule(veto),
        batch_delete_rule,
        forbidden_file_rule,
        scope_creep_rule,
        evidence_for_done_rule,
        git_commit_evidence_rule,
        git_commit_scope_rule,
        two_hats_rule,
        council_for_done_rule,
        ideation_before_write_rule,
        new_path_rule,
        effect_reversibility_rule,
      ]
    end

    # Configuration files stay editable. Their schema and constitutional
    # invariants are checked on the candidate content for every Fold write.
    # The guard is shared with lib/fix/write_guard.rb and sits outside the
    # fold's seven-file concept budget (data/spine.yml core_files), so it is
    # resolved through the shared loader rather than required from lib/.
    def self.configuration_invariant_rule(workspace_root:)
      Law.new(id: :configuration_invariant, verbs: %i[write], judge: lambda { |effect, _memory|
        reason = Master::ConfigurationGuard.validate(
          path: effect.args[:path],
          content: effect.args[:content].to_s,
          root: workspace_root,
        )
        next nil unless reason

        Verdict::Block.new(reason:, by: :configuration_invariant)
      })
    end

    # Sacred paths are declared by soul.yml, the constitutional source. The rule
    # catalogue remains descriptive and must not become a second write-protection list.
    # The agent may not rewrite the constitution it is judged by or the spine
    # that folds its effects. A write, or a git stage of such a path, is blocked.
    def self.immutable_paths_rule(immutable, master_root: nil, workspace_root: nil)
      Law.new(id: :immutable_paths, verbs: %i[write git], judge: lambda { |effect, _memory|
        targets = effect.verb == :write ? [effect.args[:path]] : Array(effect.args[:paths])
        hit = targets.compact.map(&:to_s).find do |path|
          immutable_hit?(path, immutable, master_root:, workspace_root:)
        end
        next nil unless hit

        Verdict::Block.new(reason: "immutable path: #{hit}", by: :immutable_paths)
      })
    end

    # Resolve the target exactly as World does: relative to the one workspace
    # whose boundary the effect will use. Resolve declarations relative to the
    # MASTER root that owns soul.yml. Never interpret one relative target against
    # two roots: that both overblocked unrelated paths and obscured which file
    # was actually being judged.
    def self.immutable_hit?(path, immutable, master_root: nil, workspace_root: nil)
      target = File.expand_path(path.to_s, File.expand_path(workspace_root || "/"))
      immutable.any? do |guard|
        subtree = guard.to_s.end_with?("/")
        protected_path = File.expand_path(guard.to_s.delete_suffix("/"), File.expand_path(master_root || "/"))
        subtree ? target == protected_path || target.start_with?("#{protected_path}/") : target == protected_path
      end
    end

    # No credential ever reaches disk, a transcript, a command or commit history.
    def self.no_secret_rule(veto)
      Law.new(id: :no_secret, verbs: %i[write note exec git], judge: lambda { |effect, _memory|
        pattern = veto["secrets"]
        next Verdict::Block.new(
          reason: "veto_patterns.secrets missing or invalid — effects are unjudgeable for secrets",
          by: :no_secret,
        ) unless pattern.respond_to?(:match?)

        body = [effect.args[:content], effect.args[:text], effect.args[:message],
                Array(effect.args[:argv]).map(&:to_s)].flatten.compact.join("\n")
        next nil unless body.match?(pattern)

        Verdict::Block.new(reason: "secret in effect content", by: :no_secret)
      })
    end

    # Every Ruby file the agent writes must parse. The check that was missing
    # while 109 lib files rotted; here it cannot be skipped.
    def self.ruby_parses_rule
      Law.new(id: :ruby_parses, verbs: %i[write], judge: lambda { |effect, _memory|
        next nil unless effect.args[:path].to_s.end_with?(".rb")

        err = ruby_syntax_error(effect.args[:content].to_s)
        err ? Verdict::Block.new(reason: err, by: :ruby_parses) : nil
      })
    end

    # A write may carry the debt already in the file it replaces; it may not add
    # to it. Blocking on the whole file would refuse the first repair of any file
    # that already breaks a rule.
    def self.scan_clean_rule(verify)
      Law.new(id: :scan_clean, verbs: %i[write], judge: lambda { |effect, _memory|
        blocking = verify.call(path: effect.args[:path], content: effect.args[:content].to_s)
        next nil if blocking.empty?

        Verdict::Block.new(reason: "write introduces #{blocking.join("; ")}", by: :scan_clean)
      })
    end

    # The hardened shell policy, applied to the constitutional exec path.
    #
    # Blocks on a denial only. The policy answers :deny, :ask or :allow, and :ask
    # is what it returns for anything it does not recognise — which is most real
    # commands — so treating :ask as a refusal would stop the fold running its own
    # tests. Io::Shell made the same call for the same reason; this keeps the two
    # checks saying the same thing rather than inventing a second opinion.
    # The sandbox answers one of three things, and the third is new:
    #
    #   nil                 nothing to say; later rules decide
    #   "reason"            deny, as before
    #   { ask: "reason" }   a person decides
    #
    # A Hash rather than another String, because a deny reason and an ask reason
    # would otherwise be the same value meaning opposite things. A sandbox that
    # only ever returns a String or nil keeps exactly its old behaviour.
    def self.sandboxed_exec_rule(sandbox)
      Law.new(id: :sandboxed_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        answer = sandbox.call(Array(effect.args[:argv]).map(&:to_s)) or next nil

        if answer.is_a?(Hash) && answer[:ask]
          command = Array(effect.args[:argv]).join(" ")
          next Verdict::Request.new(
            effect:,
            prompt: "run `#{command}`? (#{answer[:ask]})",
            reason: answer[:ask].to_s,
            by: :sandboxed_exec,
          )
        end

        Verdict::Block.new(reason: "sandbox denied: #{answer}", by: :sandboxed_exec)
      })
    end

    # Unsafe shell never executes.
    def self.safe_exec_rule(veto)
      Law.new(id: :safe_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
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

    # Five rules below share one shape: work out a reason from the effect, and
    # block under the rule's own id when there is one. The block returns nil to
    # pass.
    def self.reason_rule(id, verbs, &reason)
      Law.new(id:, verbs:, judge: lambda { |effect, memory|
        text = reason.call(effect, memory)
        text ? Verdict::Block.new(reason: text, by: id) : nil
      })
    end

    def self.batch_delete_rule
      reason_rule(:batch_delete, %i[exec]) { |effect, _memory| batch_delete_reason(effect.args[:argv]) }
    end

    def self.forbidden_file_reason(path)
      name = File.basename(path.to_s).downcase
      return unless FORBIDDEN_BASENAMES.include?(name)

      "forbidden file: #{name} — deliver code, not a sidecar markdown"
    end

    def self.forbidden_file_rule
      reason_rule(:forbidden_file, %i[write]) { |effect, _memory| forbidden_file_reason(effect.args[:path]) }
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
      reason_rule(:scope_creep, %i[write]) { |effect, memory| scope_creep_reason(effect.args[:path], memory.proof) }
    end

    def self.two_hats_reason(message, lines)
      return if lines.to_i <= TWO_HATS_LINES

      text = message.to_s
      return unless text.match?(FEAT_RX) && text.match?(REFACTOR_RX)

      "two hats: #{lines} lines mix a feature/fix with a refactor"
    end

    def self.two_hats_rule
      reason_rule(:two_hats, %i[git]) do |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit

        two_hats_reason(effect.args[:message], memory.proof.scope[:write_lines])
      end
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
      Law.new(id: :structured_exec, verbs: %i[exec], judge: lambda { |effect, _memory|
        argv = effect.args[:argv]
        next nil if argv.is_a?(Array) && argv.all? { |arg| arg.is_a?(String) } && !argv.empty?

        Verdict::Block.new(reason: "exec requires argv: [String, ...]", by: :structured_exec)
      })
    end

    # The agent may not declare success without evidence (no completion theater).
    # A fold that only read is answering, not claiming a change; see
    # Proof#answered_from_reads?.
    def self.evidence_for_done_rule
      Law.new(id: :evidence_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil if memory.proof.proved? || memory.proof.answered_from_reads?

        Verdict::Block.new(reason: "no passing evidence on record", by: :evidence_for_done)
      })
    end

    def self.git_commit_evidence_rule
      Law.new(id: :git_commit_evidence, verbs: %i[git], judge: lambda { |effect, memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit
        next nil if memory.proof.proved?

        Verdict::Block.new(reason: "cannot commit before evidence threshold", by: :git_commit_evidence)
      })
    end

    # A commit names what it commits.
    #
    # World refuses an unscoped commit too, and that is the guarantee; this rule
    # exists so the refusal is a stated law with a reason the model can read,
    # rather than an error surfacing from the mechanism after the attempt. The
    # index in this checkout belongs to everyone at once — other sessions, and a
    # human — so "commit whatever is staged" is never a thing the fold means.
    def self.git_commit_scope_rule
      Law.new(id: :git_commit_scope, verbs: %i[git], judge: lambda { |effect, _memory|
        next nil unless effect.args[:operation].to_s.to_sym == :commit
        next nil if Array(effect.args[:paths]).map(&:to_s).any? { |p| !p.strip.empty? }

        Verdict::Block.new(reason: "commit must name its paths; the index is shared", by: :git_commit_scope)
      })
    end

    # High-risk goals require an in-process council critique before done.
    def self.council_for_done_rule
      Law.new(id: :council_for_done, verbs: %i[done], judge: lambda { |_effect, memory|
        next nil unless memory.proof.council_required?
        next nil if memory.proof.council_cleared?

        Verdict::Block.new(reason: "run critique (council tribunal) before done on high-risk goals", by: :council_for_done)
      })
    end

    # Medium+ goals must carry ideation notes seeded before the first write.
    def self.ideation_before_write_rule
      Law.new(id: :ideation_before_write, verbs: %i[write], judge: lambda { |_effect, memory|
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
      reason_rule(:new_path_ask, %i[write]) { |effect, memory| new_path_reason(effect.args[:path], memory.proof) }
    end

    # Reversibility is derived from the actual Effect, not accepted as a model
    # assertion. Durable Git mutations require an explicit yes; an operation
    # without a World handler is blocked rather than "approved" into a dead end.
    # A compensating command is separately re-admitted and approved after failure.
    def self.effect_reversibility_rule
      Law.new(id: :effect_reversibility, verbs: VERBS, judge: lambda { |effect, _memory|
        contract = effect.reversibility
        case contract.kind
        when :approval_required
          operation = effect.verb == :git ? " git #{effect.args[:operation]}" : " #{effect.verb}"
          scope = contract.scope.to_s.empty? ? "" : " on #{contract.scope}"
          Verdict::Request.new(
            effect:,
            prompt: "Approve#{operation}#{scope}? #{contract.reason}.",
            reason: contract.reason,
            by: :effect_reversibility,
          )
        when :unknown
          Verdict::Block.new(reason: contract.reason, by: :effect_reversibility)
        end
      })
    end

    # Prism parses in-process and returns every syntax error, so no child
    # process, PATH lookup or timeout stands between the fold and its next write.
    def self.ruby_syntax_error(content)
      Prism.parse(content).errors.first&.message
    end

    # A veto pattern that does not compile would leave its rule with nothing to
    # match, so every secret or unsafe command would pass. Refuse to build the
    # constitution instead.
    def self.safe_rx(name, pattern)
      Regexp.new(pattern, Regexp::MULTILINE)
    rescue RegexpError, TypeError => e
      raise ArgumentError, "veto pattern #{name} is invalid: #{e.message}"
    end

    # The surface is load, admit, and immutable_paths_rule — which
    # test/test_core_immutable_paths.rb builds directly. The rest are rule
    # factories `default_rules` calls and nothing else does, verified against
    # lib/, test/, tools/, bin/ and web/.
    #
    # Declared rather than merely true: `private` marks a position in the
    # instance-method stream and class methods never enter it, so this class read
    # as 16 public methods under ABSTRACTION no matter how it was arranged. That
    # is the idiom being measured, not the surface — see the old backlog, "The fold spine
    # had never been scanned". Unlike Memory, this class did not need splitting:
    # its count was the idiom, and Memory's was the design.
    private_class_method :default_rules, :immutable_hit?, :configuration_invariant_rule, :no_secret_rule, :ruby_parses_rule, :scan_clean_rule, :reason_rule,
                         :safe_exec_rule, :sandboxed_exec_rule, :structured_exec_rule, :batch_delete_rule, :delete_operands,
                         :operands_after_flags, :git_clean_all?, :forbidden_file_rule, :scope_creep_rule,
                         :two_hats_rule, :evidence_for_done_rule,
                         :git_commit_evidence_rule, :git_commit_scope_rule, :council_for_done_rule,
                         :ideation_before_write_rule, :new_path_rule, :effect_reversibility_rule, :ruby_syntax_error, :safe_rx

    # One source for paths that are constitutionally protected.
    #
    # soul.yml owns identity and sacred paths. This class is deliberately small:
    # readers can ask for the declarations or whether one path is protected
    # without knowing how soul.yml is laid out.
    class Paths
      MANIFEST = "data/soul.yml"
      RATCHET_CEILING = "data/spine.yml"

      def self.sacred_paths(root:)
        new(root:).sacred_paths
      end

      def self.sacred?(path, root:)
        new(root:).sacred?(path)
      end

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def sacred_paths
        @sacred_paths ||= begin
          # Fail closed: a missing, unreadable, invalid, or empty soul.yml must
          # never degrade into "nothing is sacred" and silently disable protection.
          root = manifest_root
          raise Errno::ENOENT, "#{MANIFEST} not found under #{@root}" unless root

          soul = YAML.safe_load_file(File.join(root, MANIFEST), aliases: true)
          declared = if soul.is_a?(Hash) && soul["absolute"].is_a?(Hash)
                       Array(soul.dig("absolute", "sacred_paths"))
                     else
                       []
                     end
          if declared.empty? || declared.any? { |path| path.to_s.strip.empty? }
            raise "soul.yml under #{@root} declares no valid absolute.sacred_paths — refusing to derive empty sacred paths"
          end

          declared.map(&:to_s).map do |path|
            entry = normalize("#{manifest_prefix}#{path}")
            # normalize resolves the path and drops the slash that marks a subtree;
            # Constitution.immutable_hit? reads that slash to guard everything below.
            path.end_with?("/") ? "#{entry}/" : entry
          end.uniq.freeze
        end
      end

      def sacred?(path)
        relative = normalize(path)
        sacred_paths.any? do |entry|
          relative == entry || relative.start_with?("#{entry.delete_suffix("/")}/")
        end
      rescue StandardError
        # An uncertain path or unreadable constitution is protected until proven otherwise.
        true
      end

      # nil when a runtime commit may carry this path, else why not. The one sacred file
      # it may carry is the ceiling RatchetSponsor requires beside any change that grows
      # or shrinks a tree.
      def commit_refusal(path)
        relative = normalize(path)
        # Validate the constitution before honoring the ratchet-ceiling exception below.
        # A broken manifest must refuse every commit, including data/spine.yml.
        sacred_paths
        return unless sacred?(path)

        return if relative.delete_prefix(manifest_prefix) == RATCHET_CEILING

        "#{relative} is sacred (soul.yml absolute.sacred_paths)"
      rescue ArgumentError
        "#{path} is outside #{@root}"
      rescue StandardError => e
        "#{path} refused: constitution unreadable (#{e.class}: #{e.message.to_s[0, 80]})"
      end

      private

      def manifest_root
        @manifest_root ||= [@root, File.join(@root, "MASTER")].find do |candidate|
          File.file?(File.join(candidate, MANIFEST))
        end
      end

      def manifest_prefix = manifest_root == @root ? "" : "MASTER/"

      def normalize(path)
        full = File.expand_path(path.to_s, @root)
        raise ArgumentError, "path escapes root: #{path}" unless full == @root || full.start_with?("#{@root}/")

        full == @root ? "" : full.delete_prefix("#{@root}/")
      end
    end
  end
end
