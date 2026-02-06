# frozen_string_literal: true

module MASTER
  module Stages
    # OpenBSD Admin: Generates declarative OpenBSD configurations
    class OpenbsdAdmin
      def call(input)
        text = input[:text] || input[:original_text] || ""
        intent = input[:intent]

        # Check if this is an admin task
        unless admin_task?(text, intent)
          # Not an admin task, pass through unchanged
          return Result.ok(input)
        end

        # Detect specific admin task type
        task_type = detect_admin_task(text)

        # TODO: Implement actual config generation
        # For now, stub with a placeholder
        config = generate_config_stub(task_type, text)

        # TODO: Validate generated config syntax
        # TODO: Apply pledge/unveil constraints when writing files

        enriched = input.merge(
          admin_task: true,
          task_type: task_type,
          generated_config: config
        )

        Result.ok(enriched)
      end

      private

      def admin_task?(text, intent)
        intent == :admin || text.match?(/\b(pf|httpd|relayd|acme-client|bgpd|ospfd)\b/i)
      end

      def detect_admin_task(text)
        return :pf if text.match?(/\bpf\b/i)
        return :httpd if text.match?(/\bhttpd\b/i)
        return :relayd if text.match?(/\brelayd\b/i)
        return :acme if text.match?(/\bacme\b/i)
        :generic
      end

      def generate_config_stub(task_type, text)
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
