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

        def self.blocked?(command)
          normalized = command.gsub(/[[:space:]]+/, " ").strip.downcase
          BLOCKLIST.any? { |b| normalized.include?(b) } || command.match?(PIPE_TO_SHELL_RE)
        end
      end
    end
  end
end
