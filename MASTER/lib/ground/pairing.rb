# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "yaml"

module Master
  module Ground
    # One-time codes before personal (messaging) tools. Store lives under
    # .master/pairing/ — gitignored, never data/security/. Remote channels
    # (irc/matrix) stay visitor-public until a code is redeemed.
    module Pairing
      CONFIG_PATH = Master.data_path("security/defaults.yml").freeze
      REMOTE = %i[irc matrix].freeze
      ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
      CODE_BYTES = 8
      TOKEN_BYTES = 24
      DEFAULT_TTL = 600
      DEFAULT_ALLOWLIST = ".master/pairing/allowlist.yml"
      REDEEM_NOTICE = "paired — messaging tools on. This is not operator access. Shell stays off. For a private assistant: clone pub4, bundle exec ruby bin/cli, /pair issue, and point the PWA at your host — not the shared public face.".freeze

      module_function

      def config
        hash = (Master.load_yaml(CONFIG_PATH) || {})["pairing"]
        hash.is_a?(Hash) ? hash : {}
      rescue StandardError
        {}
      end

      def required_for_remote_channels? = config["required_for_remote_channels"] != false
      def required_for_remote?(channel) = required_for_remote_channels? && REMOTE.include?(channel.to_sym)
      def code_ttl_seconds = Integer(config["code_ttl_seconds"] || DEFAULT_TTL)
      def redeem_per_minute = Integer(config["redeem_per_minute"] || 8)
      def redeem_window_seconds = Integer(config["redeem_window_seconds"] || 60)
      def face_profile(visitor:, paired:) = visitor ? (paired ? "messaging" : "public") : "operator"
      def redeem_notice(result) = "#{REDEEM_NOTICE} subject=#{result[:subject]}"
      def allowlist_path(root = Master::ROOT) = File.expand_path(config["allowlist_path"].to_s.empty? ? DEFAULT_ALLOWLIST : config["allowlist_path"], root)
      def codes_path(root = Master::ROOT) = File.join(File.dirname(allowlist_path(root)), "codes.yml")

      def issue(root: Master::ROOT, label: nil)
        with_store_lock(root) { issue_unlocked(root:, label:) }
      end

      def issue_unlocked(root:, label:)
        code = CODE_BYTES.times.map { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
        now = Time.now.to_i
        codes = load_yaml(codes_path(root))
        codes[code] = { "issued_at" => now, "expires_at" => now + code_ttl_seconds, "label" => label.to_s }
        persist(codes_path(root), codes)
        { code:, expires_in: code_ttl_seconds, label: label.to_s }
      end

      def redeem(code, root: Master::ROOT)
        needle = code.to_s.strip.upcase
        return if needle.empty?

        with_store_lock(root) do
          codes = load_yaml(codes_path(root))
          row = codes[needle]
          return if row.nil?
          return if row["expires_at"].to_i < Time.now.to_i

          codes.delete(needle)
          persist(codes_path(root), codes)
          issue_token(row, root)
        end
      end

      # Called with the store lock already held and the pairing code already
      # spent: this mints what replaces it.
      def issue_token(row, root)
        token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
        subject = SecureRandom.hex(8)
        allow = load_yaml(allowlist_path(root))
        allow[token] = { "subject" => subject, "paired_at" => Time.now.to_i, "label" => row["label"].to_s }
        persist(allowlist_path(root), allow)
        PersonalWorkspace.ensure!(root:, subject:)
        { token:, subject:, label: row["label"].to_s }
      end

      def valid_token?(token, root: Master::ROOT) = token.to_s != "" && load_yaml(allowlist_path(root)).key?(token.to_s)
      def subject_for(token, root: Master::ROOT) = load_yaml(allowlist_path(root)).dig(token.to_s, "subject")

      def revoke(id, root: Master::ROOT)
        allow = load_yaml(allowlist_path(root))
        key = allow.key?(id.to_s) ? id.to_s : allow.find { |_token, row| row["subject"] == id.to_s }&.first
        return false unless key

        allow.delete(key)
        persist(allowlist_path(root), allow)
        true
      end

      def list(root: Master::ROOT)
        load_yaml(allowlist_path(root)).map { |_token, row| { subject: row["subject"], paired_at: row["paired_at"], label: row["label"] } }
      end

      def apply_remote!(channel)
        Fiber[:master_visitor] = true if required_for_remote?(channel) && !Fiber[:master_paired] && !Fiber[:master_elevated]
      end

      def apply_token!(token, root: Master::ROOT)
        return unless valid_token?(token, root:)

        Fiber[:master_paired] = true
        Fiber[:master_pair_subject] = subject_for(token, root:)
      end

      def status(token = nil, root: Master::ROOT)
        return { paired: valid_token?(token, root:), subject: subject_for(token, root:), profile: ToolProfile.current_name } if token.to_s != ""

        { paired: Fiber[:master_paired] == true, subject: Fiber[:master_pair_subject], profile: ToolProfile.current_name }
      end

      def load_yaml(path)
        return {} unless File.file?(path)

        data = Master.load_yaml(path)
        data.is_a?(Hash) ? data : {}
      rescue StandardError
        {}
      end

      def persist(path, data)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp.#{Process.pid}"
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |io| io.write(data.to_yaml) }
        File.rename(tmp, path)
        File.chmod(0o600, path)
        path
      end

      def with_store_lock(root)
        path = File.join(File.dirname(codes_path(root)), "store.lock")
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, File::RDWR | File::CREAT, 0o600) do |io|
          io.flock(File::LOCK_EX)
          yield
        end
      end
    end
  end
end
