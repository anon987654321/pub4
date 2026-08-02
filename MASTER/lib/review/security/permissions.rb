# frozen_string_literal: true

module Master
  module Review
    module Security
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
