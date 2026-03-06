# frozen_string_literal: true

require_relative "../review/fixer"

module MASTER
  module Commands
    module MiscCommands
      def fix_code(args)
        path = args&.strip
        path = "." if path.nil? || path.empty?

        fixer = MASTER::Review::Fixer.new(mode: :moderate)
        if File.directory?(path)
          result = fixer.fix_directory(path)
          if result.ok?
            puts result.value
          else
            puts UI.error("fix: #{result.error}")
          end
        elsif File.exist?(path)
          result = fixer.fix(path)
          if result.ok?
            puts result.value
          else
            puts UI.error("fix: #{result.error}")
          end
        else
          puts UI.error("fix: path not found: #{path}")
        end
      end
    end
  end
end
