# frozen_string_literal: true

module Master
  module Reach
    module SocialSim
      # Blocks wiring the sandbox to real messengers or external contact lists.
      module Guard
        BLOCKED_CONNECTORS = %w[snapchat whatsapp telegram signal sms imessage instagram dm].freeze
        BLOCKED_EXPORT_ROOTS = %w[/tmp /var /etc ~].freeze

        class Violation < StandardError; end

        module_function

        def assert_sandbox!(run_dir:, options: {})
          raise Violation, "run_dir required" if run_dir.to_s.strip.empty?
          raise Violation, "run_dir must stay under output/social_sim" unless sandbox_path?(run_dir)

          connector = options[:connector].to_s.downcase.strip
          raise Violation, "connector #{connector} blocked — sandbox only" if BLOCKED_CONNECTORS.include?(connector)

          phone = options[:phone].to_s.strip
          raise Violation, "real phone numbers blocked in sandbox" if phone.match?(/\+?\d{8,}/)

          export = options[:export_to].to_s.strip
          return if export.empty?

          raise Violation, "export outside sandbox blocked" unless sandbox_path?(export)
        end

        def sandbox_path?(path)
          expanded = File.expand_path(path)
          root = File.expand_path(File.join(Master::ROOT, "output", "social_sim"))
          expanded == root || expanded.start_with?("#{root}/")
        end

        def banner
          "SYNTHETIC SIM — NO REAL MESSAGING. NPC handles end with _sim."
        end
      end
    end
  end
end
