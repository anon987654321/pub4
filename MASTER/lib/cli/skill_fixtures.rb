# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Master
  module CLI
    # The fixtures a skill declares, checked before an operator may approve it.
    # A fixture is a file inside the skill's own directory (or, for a registry
    # skill with none, test/fixtures/skills): no absolute path, no "..", no
    # symlink, and no larger than MAX_BYTES. Verification is bounded to reading:
    # YAML and JSON must parse, text must be non-empty, and anything else is
    # unsupported. Nothing a fixture contains is executed.
    module SkillFixtures
      MAX_BYTES = 64 * 1024
      READERS = {
        %w[.yml .yaml] => ->(text) { YAML.safe_load(text, aliases: false) },
        %w[.json] => ->(text) { JSON.parse(text) },
        %w[.md .txt] => ->(text) { raise ArgumentError, "empty" if text.strip.empty? },
      }.freeze

      Outcome = Data.define(:ref, :status, :sha256) do
        def verified? = status == "verified"
        def to_h = { "ref" => ref, "status" => status, "sha256" => sha256 }.compact
      end

      module_function

      def verify(refs, root:)
        Array(refs).map { |ref| check(ref.to_s, File.expand_path(root)) }
      end

      def check(ref, root)
        escapes = ref.start_with?("/") || ref.split("/").include?("..")
        return Outcome.new(ref:, status: "escapes_root", sha256: nil) if escapes

        path = File.join(root, ref)
        status = refusal(path, root) || read(path)
        Outcome.new(ref:, status:, sha256: status == "verified" ? Digest::SHA256.file(path).hexdigest : nil)
      end

      def refusal(path, root)
        return "symlink" if File.symlink?(path)
        return "missing" unless File.file?(path)
        return "escapes_root" unless File.realpath(path).start_with?(File.realpath(root) + File::SEPARATOR)
        return "too_large" if File.size(path) > MAX_BYTES

        nil
      end

      def read(path)
        reader = READERS.find { |extensions, _| extensions.include?(File.extname(path).downcase) }&.last
        return "unsupported" unless reader

        reader.call(File.read(path, encoding: "UTF-8"))
        "verified"
      rescue ArgumentError, Psych::Exception, JSON::ParserError, EncodingError
        "unreadable"
      end
    end
  end
end
