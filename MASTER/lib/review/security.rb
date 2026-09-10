# frozen_string_literal: true

require "open3"

module Master
  module Review
    module Security
      module CommandGuard
        # Tokens a tool call may not execute. Not the style list: Io::Shell reads
        # BANNED_IN_ZSH out of the law to warn a human away from GNU text tools,
        # and this raises SecurityError on a shell, an interpreter or a network
        # fetcher reaching a subprocess at all. Two questions, two lists, and a
        # name on each saying which.
        #
        # Any of these can trivially reintroduce whatever the rest of this list tries to
        # prevent (bash -c with sed, curl piped to sh, python -c with inline code) — a token-level
        # blocklist is a weak boundary in general, but omitting the shells/interpreters/
        # network fetchers themselves defeats the point of having one at all.
        EXECUTION_VECTORS = %w[
          sed awk tr grep cut head tail find wc sudo doas perl ruby python python3 dd xargs
          bash sh zsh csh ksh fish curl wget nc ncat telnet
        ].freeze
        TOKEN_SPLIT = /\s+|[|&;<>()]/

        module_function

        def validate_command!(args)
          tokens = Array(args).flat_map { |arg| arg.to_s.split(TOKEN_SPLIT) }
          tokens.each do |token|
            cleaned = token.downcase.strip
            next if cleaned.empty?

            raise Master::SecurityError, "Banned terminal execution vector: #{cleaned}" if EXECUTION_VECTORS.include?(cleaned)
          end
          true
        end

        def secure_execute(args, chdir: Dir.pwd)
          validate_command!(args)
          clean_env = { "LANG" => "C", "LC_ALL" => "C" }
          stdout_and_stderr, status = Master::Io::Exec.capture2e(clean_env, *Array(args), chdir:)
          return Result.ok(stdout_and_stderr) if status.success?

          Result.err(stdout_and_stderr, category: :infrastructure)
        rescue Master::SecurityError => e
          Result.err(e.message, category: :validation)
        rescue StandardError => e
          Result.err(e.message, category: :infrastructure)
        end
      end

      class InjectionGuard

        DEFAULTS = {
          prompt_injection: [
            /ignore (?:previous|all|your) instructions/i,
            /disregard (?:your )?(?:system )?prompt/i,
            /you are now (?:a|an|in)/i,
            /pretend (?:to be|you are|you're)/i,
            /new instructions:/i,
            /\[SYSTEM\]/i,
            /###\s*SYSTEM/i,
            /(?:act|behave|respond) as (?:if )?(?:you (?:are|were)|a|an) (?!assistant|helpful)/i,
            /override (?:your )?(?:safety|guidelines|rules|instructions)/i,
            /jailbreak/i,
            /forget (?:everything|all|your)/i,
            /override (?:axiom|principle|rule)/i,
            /disregard (?:axiom|principle|rule|safety)/i,
            /new system prompt/i,
          ].freeze,
          shell_injection: /```(?:bash|sh|zsh|shell)\n.*?
            (?:rm\s+-rf|curl\b.*?\|\s*(?:bash|sh)\b|wget\b.*?\|\s*(?:bash|sh)\b)
          /imx.freeze,
        }.freeze

        ALLOWLIST_TOKEN = /\AMASTER_TRUSTED:[A-Za-z0-9]{16,}/.freeze

        def initialize(mode: :permissive)
          @mode = mode
          @patterns = load_or_default
        end

        def scan(content)
          total = @patterns[:prompt_injection].count { |p| content.match?(p) }
          total += 1 if content.match?(@patterns[:shell_injection])

          if total.zero?
            return Result.ok(:clean) if @mode == :permissive
            return Result.ok(:clean) if content.match?(ALLOWLIST_TOKEN)
            return Result.err("default_deny: no allowlist token; rejecting unmatched input", category: :validation)
          end
          Result.err("injection detected: #{total} pattern(s) matched", category: :validation)
        end

        def safe?(text) = scan(text.to_s).ok?

        def clean!(content)
          prompt_cleaned = @patterns[:prompt_injection].reduce(content) { |c, p| c.gsub(p, "[REDACTED]") }
          shell_cleaned = prompt_cleaned.gsub(@patterns[:shell_injection], "[REDACTED]")
          Result.ok(shell_cleaned)
        end

        private

        def load_or_default
          data = injection_data
          return DEFAULTS unless data

          prompt = (data["prompt_injection"] || []).map { |s| Regexp.new(s, Regexp::IGNORECASE) }
          shell = data.dig("shell_injection", "multiline_pattern")
          {
            prompt_injection: prompt.empty? ? DEFAULTS[:prompt_injection] : prompt.freeze,
            shell_injection: shell ? Regexp.new(shell, Regexp::MULTILINE | Regexp::IGNORECASE) : DEFAULTS[:shell_injection],
          }
        rescue StandardError
          DEFAULTS
        end

        def injection_data
          merged = Master.law("injection")
          merged if merged.is_a?(Hash) && !merged.empty?
        end
      end

      module Permissions
        TOOL_TIERS = {
          "read_file" => :safe,
          "list_dir" => :safe,
          "search_files" => :safe,
          "write_file" => :guarded,
          "str_replace" => :guarded,
          "apply_diff" => :guarded,
          "ask_llm" => :guarded,
          "web_search" => :guarded,
          "zsh" => :dangerous,
        }.freeze

        BLOCKLIST = [
          "sudo",
          "reboot",
          "shutdown",
          "halt",
          "poweroff",
          "> /dev/",
          "chmod 777",
          "chmod -r 777",
          "curl | sh",
          "wget | sh",
          "chown root",
          "passwd root",
          "visudo",
        ].freeze

        def self.tier_for(tool_name)
          TOOL_TIERS[tool_name.to_s] || :guarded
        end

        PIPE_TO_SHELL_RE = /\|\s*(?:ba|z)?sh\b/i.freeze

        # Bare-word entries match on word boundaries; entries holding an operator or
        # a path stay literal substrings. Plain `include?` blocked by accident —
        # "sudo" is inside "pseudo", "halt" inside "shalt" — so `grep -rn
        # shutdown_handler lib` was refused as dangerous.
        BLOCK_MATCHERS = BLOCKLIST.map do |entry|
          entry.match?(/\A[a-z0-9 ]+\z/) ? /\b#{Regexp.escape(entry)}\b/ : entry
        end.freeze

        def self.blocked?(command)
          normalized = command.gsub(/[[:space:]]+/, " ").strip.downcase
          matched = BLOCK_MATCHERS.any? do |matcher|
            matcher.is_a?(Regexp) ? normalized.match?(matcher) : normalized.include?(matcher)
          end
          matched || command.match?(PIPE_TO_SHELL_RE)
        end
      end
    end
  end
end
