# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "securerandom"
require_relative "measure"

module Master
  module Convergence
    module Receipt
      module_function

      def write(root: Master::REPO_ROOT, command:, state:, details: {})
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
        id = "#{stamp}-#{Process.pid}-#{SecureRandom.hex(4)}"
        payload = {
          schema: 1,
          id: id,
          command: command.to_s,
          state: state.to_s,
          generated_at: Time.now.utc.iso8601,
          git: git_identity(root),
          inventory: Measure.inventory(root:),
          details: json_safe(details),
        }
        path = File.join(root, ".master", "receipts", "convergence-#{id}.json")
        FileUtils.mkdir_p(File.dirname(path))
        body = JSON.pretty_generate(payload) << "\n"
        File.write(path, body, mode: "w:UTF-8")
        { id:, path:, sha256: Digest::SHA256.hexdigest(body), payload: }
      end

      def recent(root: Master::REPO_ROOT, limit: 10)
        directory = File.join(root, ".master", "receipts")
        return [] unless File.directory?(directory)

        Dir.glob(File.join(directory, "convergence-*.json")).sort.reverse.first(limit.to_i).filter_map do |path|
          JSON.parse(File.read(path, encoding: "UTF-8"))
        rescue JSON::ParserError, EncodingError
          nil
        end
      end

      def trend(root: Master::REPO_ROOT, limit: 10)
        rows = recent(root:, limit:)
        rows.each_cons(2).filter_map do |newer, older|
          before = older.dig("inventory", "totals")
          after = newer.dig("inventory", "totals")
          next unless before && after

          {
            id: newer["id"],
            newer_state: newer["state"],
            files_delta: after["files"].to_i - before["files"].to_i,
            bytes_delta: after["bytes"].to_i - before["bytes"].to_i,
          }
        end
      end

      def git_identity(root)
        {
          head: Measure.inventory(root:)[:git],
          branch: capture_git(root, "symbolic-ref", "--short", "HEAD"),
          dirty: !capture_git(root, "status", "--porcelain").to_s.strip.empty?,
        }
      end

      def capture_git(root, *args)
        out, status = Master::Io::Exec.capture2e("git", "-C", root, *args)
        status.success? ? out.strip : nil
      rescue StandardError
        nil
      end

      def json_safe(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, json_safe(item)] }
        when Array then value.map { |item| json_safe(item) }
        when Symbol then value.to_s
        else value
        end
      end
    end
  end
end
