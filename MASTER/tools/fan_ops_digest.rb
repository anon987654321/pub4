#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "date"
require "fileutils"
require "mail"
require "net/imap"
require "yaml"
require_relative "fan_ops_digest_support"

ROOT = File.expand_path("..", __dir__).freeze
CONFIG = YAML.safe_load_file(File.join(ROOT, "data", "fan_ops.yml"), aliases: false).freeze
OPERATOR = YAML.safe_load_file(File.join(ROOT, "data", "operator_model.yml"), aliases: false).freeze

module Master
  module FanOps
    class Digest
      def initialize(config:, operator:, env: ENV, now: Time.now)
        @config = config
        @operator = operator
        @env = env
        @now = now
        @guard = Guard.new(config:)
        @extractor = Extractor.new(config:)
        @dossier = Dossier.new(path: File.join(ROOT, config.dig("caps", "store")))
      end

      def run!
        ensure_read_only_contract!
        client = connect
        lines = header
        count = 0

        unseen_since(client).each do |id|
          mail = Mail.read_from_string(fetch_raw(client, id))
          next unless @extractor.allowed?(mail)

          event = @extractor.parse(mail)
          next unless event

          body = text_body(mail)
          if @guard.minor_cue?(body) || @guard.minor_cue?(mail.subject.to_s)
            @dossier.record(event.merge(event: "ESCALATE"))
            lines.concat([
              "## #{event[:handle]} — possible minor cue",
              "No draft generated. Review manually; do not engage from this digest.",
              "",
            ])
            next
          end

          if @guard.injection?(body) || @guard.injection?(mail.subject.to_s)
            @dossier.record(event)
            lines.concat([
              "## #{event[:handle]} — injection pattern detected",
              "Dossier updated. No draft generated.",
              "",
            ])
            next
          end

          if off_limits?(body, mail.subject.to_s)
            @dossier.record(event)
            lines.concat([
              "## #{event[:handle]} — off-limits topic",
              "No draft generated.",
              "",
            ])
            next
          end

          @dossier.record(event)
          if QuietHours.blocked?(@operator.dig("boundaries", "never_nudge_hours"), @now)
            lines.concat([
              "## #{event[:handle]} (#{event[:platform]}) — #{event[:event]}",
              "No draft: quiet hours are active.",
              "",
            ])
            next
          end

          template = @config.dig("draft_templates", event[:event]) || {}
          variant = @operator.dig("register", "verbosity").to_s == "terse" ? "terse" : "warm"
          draft = template[variant] || template["warm"]
          draft = draft.to_s.gsub("{handle}", event[:handle])
          context = @dossier.context(event[:handle])
          lines.concat([
            "## #{event[:handle]} (#{event[:platform]}) — #{event[:event]}",
            "history: #{context.inspect}",
            "draft: #{draft}",
            "raw:",
            @guard.spotlight(body[0, 300]),
            "",
          ])
          count += 1
          break if count >= @config.dig("caps", "drafts_per_digest").to_i
        end

        write_digest(lines)
        puts "fan-ops digest: #{count} drafts, read-only; human sends"
      rescue Net::IMAP::Error, SocketError => e
        warn "fan-ops digest: #{e.class}: #{e.message}"
        exit 1
      ensure
        begin
          client&.logout
        rescue StandardError
          nil
        end
      end

      private

      def ensure_read_only_contract!
        raise "fan-ops send path is forbidden" if self.class.instance_methods(false).any? { |name| name.to_s.match?(/send|post|deliver/i) }
        raise "fan-ops requires explicit mailbox credentials" unless @config.dig("mailbox", "host_env") && @config.dig("mailbox", "user_env") && @config.dig("mailbox", "pass_env")
      end

      def connect
        host = @env.fetch(@config.dig("mailbox", "host_env"))
        user = @env.fetch(@config.dig("mailbox", "user_env"))
        pass = @env.fetch(@config.dig("mailbox", "pass_env"))
        Net::IMAP.new(host, port: 993, ssl: true).tap do |imap|
          imap.login(user, pass)
          imap.select(@config.dig("mailbox", "folder").to_s)
        end
      end

      def unseen_since(client)
        lookback = @config.dig("mailbox", "lookback_days").to_i
        since = (@now.to_date - lookback).strftime("%d-%b-%Y")
        client.search(["UNSEEN", "SINCE", since]) || []
      end

      def fetch_raw(client, id)
        data = client.fetch(id, "BODY.PEEK[]").fetch(0).attr
        data.fetch("BODY[]") { data.fetch("BODY.PEEK[]") }
      end

      def text_body(mail)
        return mail.text_part.decoded.to_s.strip if mail.text_part
        return mail.decoded.to_s.strip if mail.multipart? == false

        mail.parts.filter_map { |part| part.text_part ? part.text_part.decoded.to_s : nil }.join("\n").strip
      end

      def off_limits?(body, subject)
        text = [subject, body].join(" ")
        topics = Array(@operator.dig("boundaries", "topics_off_limits_for_drafts"))
        topics.any? { |topic| text.match?(/\b#{Regexp.escape(topic.to_s)}\b/i) }
      end

      def header
        [
          "# Fan-ops digest",
          "",
          "_Read-only lane. Nothing was sent. The human is the sender._",
          "",
        ]
      end

      def write_digest(lines)
        path = File.join(ROOT, @config.dig("caps", "output"))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, lines.join("\n") + "\n", mode: "w", perm: 0o600)
      end
    end
  end
end

Master::FanOps::Digest.new(config: CONFIG, operator: OPERATOR).run!
