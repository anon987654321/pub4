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

      module_function

      def config
        hash = (Master.load_yaml(CONFIG_PATH) || {})["pairing"]
        hash.is_a?(Hash) ? hash : {}
      rescue StandardError
        {}
      end

      def required_for_remote_channels?
        config["required_for_remote_channels"] != false
      end

      def required_for_remote?(channel)
        required_for_remote_channels? && REMOTE.include?(channel.to_sym)
      end

      def code_ttl_seconds
        Integer(config["code_ttl_seconds"] || DEFAULT_TTL)
      end

      def allowlist_path(root = Master::ROOT)
        rel = config["allowlist_path"].to_s
        rel = DEFAULT_ALLOWLIST if rel.empty?
        File.expand_path(rel, root)
      end

      def codes_path(root = Master::ROOT)
        File.join(File.dirname(allowlist_path(root)), "codes.yml")
      end

      def issue(root: Master::ROOT, label: nil)
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

        codes = load_yaml(codes_path(root))
        row = codes[needle]
        return if row.nil?
        return if row["expires_at"].to_i < Time.now.to_i

        codes.delete(needle)
        persist(codes_path(root), codes)
        token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
        subject = SecureRandom.hex(8)
        allow = load_yaml(allowlist_path(root))
        allow[token] = {
          "subject" => subject,
          "paired_at" => Time.now.to_i,
          "label" => row["label"].to_s,
        }
        persist(allowlist_path(root), allow)
        PersonalWorkspace.ensure!(root:, subject:)
        { token:, subject:, label: row["label"].to_s }
      end

      def valid_token?(token, root: Master::ROOT)
        return false if token.to_s.empty?

        load_yaml(allowlist_path(root)).key?(token.to_s)
      end

      def subject_for(token, root: Master::ROOT)
        load_yaml(allowlist_path(root)).dig(token.to_s, "subject")
      end

      def revoke(token, root: Master::ROOT)
        allow = load_yaml(allowlist_path(root))
        removed = allow.delete(token.to_s)
        persist(allowlist_path(root), allow)
        !removed.nil?
      end

      def list(root: Master::ROOT)
        load_yaml(allowlist_path(root)).map do |token, row|
          { token: "#{token[0, 6]}…", subject: row["subject"], paired_at: row["paired_at"], label: row["label"] }
        end
      end

      def apply_remote!(channel)
        return unless required_for_remote?(channel)
        return if Fiber[:master_paired] || Fiber[:master_elevated]

        Fiber[:master_visitor] = true
      end

      def apply_token!(token, root: Master::ROOT)
        return unless valid_token?(token, root:)

        Fiber[:master_paired] = true
        Fiber[:master_pair_subject] = subject_for(token, root:)
        true
      end

      def status(token = nil, root: Master::ROOT)
        if token.to_s.empty?
          return { paired: false, profile: ToolProfile.current_name } unless Fiber[:master_paired]

          return { paired: true, subject: Fiber[:master_pair_subject], profile: ToolProfile.current_name }
        end

        { paired: valid_token?(token, root:), subject: subject_for(token, root:), profile: ToolProfile.current_name }
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
    end
  end
end
