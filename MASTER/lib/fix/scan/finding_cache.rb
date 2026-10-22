# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../../trace/dmesg"

module Master
  module Fix
    module Scan
      # JSON that keeps what a law returns: Findings, symbols, and hashes with symbol keys, which plain
      # JSON would turn into strings and so into findings no reader matches. laws.yml forbids Marshal.
      module FindingCodec
        SCALARS = [String, Integer, Float, TrueClass, FalseClass, NilClass].freeze

        ENCODERS = {
          Symbol => ->(value) { { "$sym" => value.to_s } },
          Hash => ->(value) { { "$hash" => value.map { |key, item| [encode(key), encode(item)] } } },
          Array => ->(value) { value.map { |item| encode(item) } },
          Master::Review::Scan::Finding => ->(value) { { "$finding" => encode_fields(value) } },
        }.freeze

        module_function

        def encode(value)
          return value if SCALARS.include?(value.class)

          encoder = ENCODERS.fetch(value.class) { raise TypeError, "uncacheable #{value.class}" }
          encoder.call(value)
        end

        def encode_fields(finding)
          finding.class.members.to_h { |name| [name.to_s, encode(finding.public_send(name))] }
        end

        def decode(value)
          return value.map { |item| decode(item) } if value.is_a?(Array)
          return value unless value.is_a?(Hash)

          decode_tagged(value)
        end

        def decode_tagged(value)
          return value.fetch("$sym").to_sym if value.key?("$sym")
          return value.fetch("$hash").to_h { |key, item| [decode(key), decode(item)] } if value.key?("$hash")

          fields = value.fetch("$finding").to_h { |name, item| [name.to_sym, decode(item)] }
          Master::Review::Scan::Finding.new(**fields)
        end
      end

      # The lexical and structural findings of a file whose text has not changed since the last scan.
      # Every /fix run re-read the whole tree with every law, 172 files of lib/fix alone costing 21 seconds
      # warm, though a law that reads only the file's text and path must give the same answer twice.

      # The key is the file's path and content, the set of laws asked, and the scanner's own source: the
      # law code, laws.yml and the linter configs. A change to any of them asks again. Only laws that
      # declare they read nothing else (Law.reads_beyond_file?) are replayed; the others run every time.
      # One entry per path, overwritten when its key changes, so the cache holds one answer per file.
      # MASTER_SCAN_CACHE=0 turns it off.
      class FindingCache
        DIR = File.join(".master", "scan_findings")
        SOURCES = %w[lib/review/**/*.rb lib/fix/scan/**/*.rb law/**/*.rb data/laws.yml
                     .rubocop.yml .reek.yml config.reek Gemfile.lock].freeze

        def self.enabled? = ENV["MASTER_SCAN_CACHE"] != "0"

        # The law code this process loaded, so it is read once: an edit to a law mid-run does not change
        # the code already running, and the next process sees the new digest.
        def self.signature(root)
          @signature ||= {}
          @signature[root] ||= begin
            files = SOURCES.flat_map { |glob| Dir.glob(File.join(root, glob)) }.select { |path| File.file?(path) }
            parts = files.sort.map { |path| "#{path.delete_prefix(root)}\0#{Digest::SHA256.file(path).hexdigest}" }

            Digest::SHA256.hexdigest([RUBY_VERSION, ENV["MASTER_EXTERNAL_LINT"], *parts].join("\n"))
          end
        end

        def initialize(root: Master::ROOT)
          @root = root
          @dir = File.join(root, DIR)
        end

        def cacheable?(law) = self.class.enabled? && !law.class.reads_beyond_file?

        # The block's findings, from disk when this content was asked these laws before.
        def fetch(relative, code:, laws:, ast:)
          return yield unless self.class.enabled? && !laws.empty?

          path = File.join(@dir, "#{Digest::SHA256.hexdigest(relative)}.json")
          key = key(relative, code:, laws:, ast:)
          hit = read(path, key)
          return hit unless hit.nil?

          findings = yield
          write(path, key:, findings:)
          findings
        end

        private

        def key(relative, code:, laws:, ast:)
          ids = laws.map { |law| law.id.to_s }.sort
          Digest::SHA256.hexdigest([self.class.signature(@root), relative, Digest::SHA256.hexdigest(code),
                                    ast ? "ast" : "text", *ids].join("\n"))
        end

        def read(path, key)
          return unless File.file?(path)

          entry = JSON.parse(File.read(path, encoding: "UTF-8"))
          FindingCodec.decode(entry.fetch("findings")) if entry["key"] == key
        rescue StandardError => e
          Master::Trace::Dmesg.status("scan0", "finding cache entry unreadable, rescanning: #{e.message[0, 80]}")
          nil
        end

        # A finding holding something the codec cannot spell (a law that returns a Proc) is not kept.
        def write(path, key:, findings:)
          data = JSON.generate("key" => key, "findings" => FindingCodec.encode(findings))

          FileUtils.mkdir_p(@dir)
          temp = "#{path}.#{Process.pid}.#{Thread.current.object_id}"
          File.write(temp, data)
          File.rename(temp, path)

        rescue TypeError, SystemCallError => e
          Master::Trace::Dmesg.status("scan0", "finding cache not written: #{e.message[0, 80]}")
        end
      end
    end
  end
end
