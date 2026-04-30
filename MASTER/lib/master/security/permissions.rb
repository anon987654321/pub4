# frozen_string_literal: true

module Master
  module Security
    module Permissions
      TOOL_TIERS = {
        "read_file"    => :safe,
        "list_dir"     => :safe,
        "search_files" => :safe,
        "write_file"   => :guarded,
        "str_replace"  => :guarded,
        "apply_diff"   => :guarded,
        "ask_llm"      => :guarded,
        "web_search"   => :guarded,
        "zsh"          => :dangerous
      }.freeze

      BLOCKLIST = [
        "rm -rf /",
        "sudo",
        "reboot",
        "shutdown",
        "mkfs",
        "dd if=",
        "> /dev/",
        "chmod 777",
        "curl | sh",
        "wget | sh"
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
