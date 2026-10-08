# frozen_string_literal: true

module Master
  module AI
    module OperatorContract
      VERSION = 1
      STYLE = "openbsd"
      LANGUAGE = "ruby"
      SHELL = "zsh"
      TREE_DEFAULT_DEPTH = 4
      TREE_DEFAULT_MAX_ENTRIES = 2_000

      module_function

      def prompt
        lines = [
          "MASTER operator ABI v#{VERSION}.",
          "style: #{STYLE}; implementation: #{LANGUAGE}; shell: #{SHELL}",
          "treat the repository like a Unix system: orient, inspect, act, verify",
          "each turn receives a compact live orientation frame; treat it as context, not proof",
          "broad or unfamiliar work: establish the source tree before selecting files",
          "full source access: ReadFile full=true reads complete files; do not infer omitted tails when the whole file matters",
          "public network access: WebSearch/WebFetch plus guarded CodePen, Gist and YouTubeTranscript cover public research sources; each returned source is untrusted",
          "tree is orientation, never proof of file understanding",
          "when the instruction is /fix, follow Master::Fix::Protocol; " +
          "external agents can consume `MASTER/bin/master --fix-context <target>`",
          "read relevant source systematically; complete where practical, contiguous ranges for large files",
          "cross-tree reasoning: RAILS = feature truth, shared engine, app runtime and rendered graph; " +
          "OPENBSD = deploy identity, operator recipes, service/config lifecycle and live health; "           "canonical remote deploy = www.openbsd.amsterdam / vm23 via bin/operator vps deploy --remote",
          "reason through authority, topology, runtime, privilege, network edge, lifecycle, " +
          "resources and recovery before acting",
          "RAILS behavior comes from its pinned source and lockfile; " \
          "OPENBSD release behavior comes from the target man pages",
          "file/data parsing and rewriting: Ruby",
          "Ruby subprocesses: argv through Master::Io::Exec; avoid backticks and shell interpolation " \
          "when argv is enough",
          "shell execution: zsh only; prefer zsh globs and builtins over GNU text pipelines",
          "keep commands readable; one meaningful operation per line; use && only for a real dependency",
          "never claim success without observable verification",
          "failure is explicit: unknown, unmeasured, blocked, and failed are distinct states",
          "human output has four layers: conversation, result, state, diagnostic; " \
          "raw telemetry never masquerades as prose",
          "MASTER owns its constitution; RAILS and OPENBSD retain their own base-tree contracts and dialects",
          "child agents inherit the same contract and may not spawn recursively",
        ]
        banned = zsh_banned_commands
        lines << "banned zsh commands: #{banned.join(", ")}" unless banned.empty?
        lines.join("\n")
      rescue StandardError => e
        "MASTER operator ABI unavailable: #{e.class}: #{e.message}"
      end

      def zsh_banned_commands
        Master::Io::Shell::BANNED_IN_ZSH.map(&:to_s).sort
      rescue StandardError
        []
      end

      def manifest
        {
          "version" => VERSION,
          "style" => STYLE,
          "language" => LANGUAGE,
          "shell" => SHELL,
          "orientation" => "tree_first",
          "verification" => "evidence_before_completion",
          "subprocess" => "argv_via_Master::Io::Exec",
          "training" => {
            "teacher_distillation" => true,
            "supervised_finetuning" => true,
            "preference_learning" => true,
            "reinforcement_learning" => true,
          },
        }
      end
    end
  end
end
