# frozen_string_literal: true

module Master
  module Ground
    # Webhook + cron ingress definitions (OpenCrabs cron DSL / OpenClaw hooks parity).
    module IngressJobs
      PATTERNS_PATH = File.join(Master::ROOT, "data", "patterns.yml").freeze

      module_function

      def cron_jobs
        load_jobs("cron_jobs", kind: "cron")
      end

      def webhook_jobs
        load_jobs("webhooks", kind: "webhook")
      end

      def lookup_cron(name)
        cron_jobs.find { |job| job["name"].to_s == name.to_s }
      end

      def lookup_webhook(name)
        webhook_jobs.find { |job| job["name"].to_s == name.to_s }
      end

      def load_jobs(section, kind:)
        return [] unless File.file?(PATTERNS_PATH)

        rows = (Master.load_yaml(PATTERNS_PATH) || {})[section]
        return [] unless rows.is_a?(Array)

        rows.select do |row|
          row.is_a?(Hash) && row["enabled"] != false && !row["name"].to_s.empty? &&
            (row["kind"].nil? || row["kind"].to_s == kind)
        end
      rescue StandardError => e
        Swallow.log(e, context: "ingress_jobs.load", path: PATTERNS_PATH)
        []
      end
    end
  end
end
