# frozen_string_literal: true

module Master
  module Judge
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
          "zsh" => :dangerous
        }.freeze

        BLOCKLIST = [
          "rm -rf",
          "sudo",
          "doas",
          "reboot",
          "shutdown",
          "halt",
          "poweroff",
          "mkfs",
          "dd if=",
          "> /dev/",
          "chmod 777",
          "chmod -R 777",
          "curl | sh",
          "curl|sh",
          "wget | sh",
          "wget|sh",
          "| bash",
          "|bash",
          "| zsh",
          "|zsh",
          "chown root",
          "passwd root",
          "visudo"
        ].freeze

        def self.tier_for(tool_name)
          TOOL_TIERS[tool_name.to_s] || :guarded
        end

        def self.blocked?(command)
          BLOCKLIST.any? { |b| command.downcase.include?(b.downcase) }
        end
      end
    end
  end
end
