# frozen_string_literal: true

module Master
  module Ground
    # Webhook + cron ingress definitions (OpenCrabs cron DSL / OpenClaw hooks parity).
    module IngressJobs
      CRON_PATH = File.join(Master::ROOT, "data", "cron_jobs.yml").freeze
      WEBHOOK_PATH = File.join(Master::ROOT, "data", "webhooks.yml").freeze

      module_function

      def cron_jobs
        load_jobs(CRON_PATH, kind: "cron")
      end

      def webhook_jobs
        load_jobs(WEBHOOK_PATH, kind: "webhook")
      end

      def lookup_cron(name)
        cron_jobs.find { |job| job["name"].to_s == name.to_s }
      end

      def lookup_webhook(name)
        webhook_jobs.find { |job| job["name"].to_s == name.to_s }
      end

      def load_jobs(path, kind:)
        return [] unless File.file?(path)

        rows = Master.load_yaml(path)
        return [] unless rows.is_a?(Array)

        rows.select do |row|
          row.is_a?(Hash) && row["enabled"] != false && !row["name"].to_s.empty? &&
            (row["kind"].nil? || row["kind"].to_s == kind)
        end
      rescue StandardError => e
        Swallow.log(e, context: "ingress_jobs.load", path:)
        []
      end
    end
  end
end