# frozen_string_literal: true

module MASTER
  module Stages
    # OpenBSD Admin: Generates declarative OpenBSD configurations
    class Admin
      include Dry::Monads[:result]

      def call(input)
        text = input[:text] || input[:original_text] || ""
        intent = input[:intent]

        # Check if this is an admin task
        unless admin?(text, intent)
          # Not an admin task, pass through unchanged
          return Success(input)
        end

        # Detect specific admin task type
        task_type = detect(text)

        # TODO: Implement actual config generation
        # For now, stub with a placeholder
        config = stub_config(task_type, text)

        # TODO: Validate generated config syntax
        # TODO: Apply pledge/unveil constraints when writing files

        enriched = input.merge(
          admin_task: true,
          task_type: task_type,
          generated_config: config
        )

        Success(enriched)
      end

      private

      def admin?(text, intent)
        return true if intent == :admin
        
        # Use patterns from DB
        config_paths = DB.openbsd_patterns(category: "config_paths")
        services = config_paths.map { |p| p["key"] }.compact
        
        # Build dynamic pattern from DB data
        return false if services.empty?
        pattern = /\b(#{services.join("|")})\b/i
        text.match?(pattern)
      rescue
        # Fallback to hardcoded patterns if DB query fails
        text.match?(/\b(pf|httpd|relayd|acme-client|bgpd|ospfd)\b/i)
      end

      def detect(text)
        # Try to detect from DB patterns first
        config_paths = DB.openbsd_patterns(category: "config_paths")
        config_paths.each do |pattern|
          key = pattern["key"]
          return key.to_sym if text.match?(/\b#{Regexp.escape(key)}\b/i)
        end
        
        # Fallback to basic detection
        return :pf if text.match?(/\bpf\b/i)
        return :httpd if text.match?(/\bhttpd\b/i)
        return :relayd if text.match?(/\brelayd\b/i)
        return :acme if text.match?(/\bacme\b/i)
        :generic
      rescue
        :generic
      end

      def stub_config(task_type, _text)
        case task_type
        when :pf
          "# TODO: Generate pf.conf based on requirements"
        when :httpd
          "# TODO: Generate httpd.conf based on requirements"
        when :relayd
          "# TODO: Generate relayd.conf based on requirements"
        else
          "# TODO: Generate OpenBSD config for #{task_type}"
        end
      end
    end
  end
end
