# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../../trace/dmesg"
require_relative "../../ground/library_verify"

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
      # One entry per path and set of laws asked, overwritten when its key changes. One per path alone let
      # two walks asking different laws of a file overwrite each other, and the self-findings ratchet
      # missed half its files on a second run over an unchanged tree.
      # MASTER_SCAN_CACHE=0 turns it off.
      class FindingCache
        # One file's text, the laws asked about it, and whether they read it parsed.
        Subject = Data.define(:relative, :code, :laws, :ast)

        DIR = File.join(".master", "scan_findings")
        # Every file a cacheable law reads besides the one it judges; test_finding_cache_inputs
        # traces the laws and fails when one reads a file missing here. data/tokens.yml is
        # CHOICE_OVERLOAD's, through Design::Thresholds, and replayed stale findings after a
        # token edit until it was added; a nested .rubocop.yml governs RuboCop below it.
        SOURCES = %w[lib/review/**/*.rb lib/fix/scan/**/*.rb law/**/*.rb data/laws.yml data/tokens.yml
                     **/.rubocop.yml .reek.yml config.reek].freeze

        def self.enabled? = ENV["MASTER_SCAN_CACHE"] != "0"

        # The law code this process loaded, so it is read once: an edit to a law mid-run does not change
        # the code already running, and the next process sees the new digest.
        def self.signature(root)
          @signature ||= {}
          @signature[root] ||= begin
            files = SOURCES.flat_map { |glob| Dir.glob(File.join(root, glob)) }.select { |path| File.file?(path) }
            parts = files.sort.map { |path| "#{path.delete_prefix(root)}\0#{Digest::SHA256.file(path).hexdigest}" }

            # The lock by its pinned versions: its constraint lines flip between bundlers with no change.
            gems = Master::Ground::LibraryVerify.pinned_digest(File.join(root, "Gemfile.lock"))
            Digest::SHA256.hexdigest([RUBY_VERSION, ENV["MASTER_EXTERNAL_LINT"], gems, *parts].join("\n"))
          end
        end

        def initialize(root: Master::ROOT, dir: DIR)
          @root = root
          @dir = File.join(root, dir)
        end

        # Asked of the Law, not its class: every canonical Law shares one adapter
        # class and only its definition knows. A bare detector class answers too.
        def cacheable?(law)
          return false unless self.class.enabled?

          !(law.respond_to?(:reads_beyond_file?) ? law.reads_beyond_file? : law.class.reads_beyond_file?)
        end

        # The block's findings, from disk when this content was asked these laws before.
        def fetch(subject)
          return yield unless self.class.enabled? && !subject.laws.empty?

          hit = replay(subject)
          return hit unless hit.nil?

          findings = yield
          record(subject, findings)
          findings
        end

        # The findings these laws gave this content last time, or nil when they have not been asked.
        def replay(subject)
          return unless self.class.enabled? && !subject.laws.empty?

          read(entry_path(subject), key(subject))
        end

        # A linter that failed to answer is not an answer: kept, its "scan error" replayed on unchanged text
        # long after the linter recovered, and refused a commit whose file rubocop judged cleanly.
        def record(subject, findings)
          return unless self.class.enabled? && !subject.laws.empty?
          return if Array(findings).any? { |finding| scan_error?(finding) }

          write(entry_path(subject), key: key(subject), findings:)
        end

        private

        def scan_error?(finding)
          finding.to_h[:message].to_s.include?(": scan error")
        end

        def entry_path(subject)
          asked = subject.laws.map { |law| law.id.to_s }.sort
          File.join(@dir, "#{Digest::SHA256.hexdigest([subject.relative, *asked].join("\n"))}.json")
        end

        def key(subject)
          ids = subject.laws.map { |law| law.id.to_s }.sort
          text = Digest::SHA256.hexdigest(subject.code)
          Digest::SHA256.hexdigest([self.class.signature(@root), subject.relative, text,
                                    subject.ast ? "ast" : "text", *ids].join("\n"))
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
