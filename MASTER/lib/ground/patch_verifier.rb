# frozen_string_literal: true

module Master
  module Ground
    class PatchVerifier
      Check = Struct.new(:kind, :target, :ok, :detail, keyword_init: true)

      def initialize(root: Master::ROOT)
        @root = root
      end

      def verify(files: [], symbols: [], references: {})
        checks = []
        checks.concat(Array(files).map { |path| check_file(path) })
        checks.concat(Array(symbols).map { |name| check_symbol(name) })
        references.each { |file, needles| checks.concat(Array(needles).map { |needle| check_reference(file, needle) }) }
        checks
      end

      def ok?(checks)
        checks.all?(&:ok)
      end

      def report(checks)
        checks.map do |check|
          status = check.ok ? "ok" : "missing"
          "#{status}: #{check.kind} #{check.target}#{check.detail ? " — #{check.detail}" : ""}"
        end
      end

      private

      def check_file(path)
        abs = File.join(@root, path.to_s)
        Check.new(kind: :file, target: path, ok: File.file?(abs), detail: nil)
      end

      def check_symbol(name)
        needle = name.to_s.split("::").last
        files = Dir.glob(File.join(@root, "lib", "**", "*.rb"))
        hit = files.find { |file| File.read(file, encoding: "utf-8").include?(needle) }
        Check.new(kind: :symbol, target: name, ok: !!hit, detail: hit && relative(hit))
      rescue StandardError => e
        Check.new(kind: :symbol, target: name, ok: false, detail: e.message)
      end

      def check_reference(file, needle)
        path = File.join(@root, file.to_s)
        ok = File.file?(path) && File.read(path, encoding: "utf-8").include?(needle.to_s)
        Check.new(kind: :reference, target: "#{file}:#{needle}", ok: ok, detail: nil)
      rescue StandardError => e
        Check.new(kind: :reference, target: "#{file}:#{needle}", ok: false, detail: e.message)
      end

      def relative(path)
        path.sub(%r{\A#{Regexp.escape(@root)}/?}, "")
      end
    end
  end
end
