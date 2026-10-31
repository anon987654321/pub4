# frozen_string_literal: true

require "pathname"
require "securerandom"
require "tmpdir"
require "fix/scanner"
require "fix/scan/source_override"

# The MASTER law API's one operation: judge source text by the same
# deterministic laws `bin/operator lint` applies (lexical, AST and law/, no
# model, no autofix). Nothing is written to disk: each file is scanned under a
# virtual path through Fix::Scan::SourceOverride, so the client's path still
# picks the language and the path-scoped laws.
#
# One scanner, one scan at a time: the box has one core, and a queue of scans
# is cheaper than a pool of scanners each holding the law tree in memory.
module LawCheck
  MAX_FILES = 20
  MAX_BYTES = 100_000
  MAX_PATH = 200
  Input = Data.define(:path, :source)

  class Invalid < StandardError; end

  LOCK = Mutex.new

  module_function

  # [Input] from the request's files, or Invalid naming what is wrong.
  def inputs(files)
    files = files.is_a?(Array) ? files : []
    raise Invalid, "files: give 1 to #{MAX_FILES}" unless files.size.between?(1, MAX_FILES)

    files.map { |file| Input.new(path: clean_path(file[:path] || file["path"]), source: clean_source(file)) }
  end

  # [{path:, line:, law:, severity:, message:}] for +inputs+, in path and line order.
  def call(inputs)
    root = File.join(Dir.tmpdir, "master-law-api", SecureRandom.hex(8))
    LOCK.synchronize do
      inputs.flat_map do |input|
        virtual = File.join(root, input.path)
        findings_for(virtual, input.source).map { |finding| row(input.path, finding) }
      end
    end.sort_by { |finding| [finding[:path], finding[:line]] }
  end

  def findings_for(virtual, source)
    result = Master::Fix::Scan::SourceOverride.with(virtual => source) { scanner.scan(virtual, depth: :deep) }
    result.ok? ? Array(result.value!) : []
  end

  def scanner = (@scanner ||= Master::Fix::Scanner.build(root: Master::ROOT, agent: nil))

  def row(path, finding)
    { path:, line: finding[:line].to_i, law: finding[:law].to_s, severity: finding[:severity].to_s,
      message: finding[:message].to_s }
  end

  # A relative path that stays inside the virtual root.
  def clean_path(path)
    path = path.to_s
    clean = Pathname.new(path).cleanpath
    invalid = path.empty? || path.size > MAX_PATH || path.include?("\0") || clean.absolute? ||
              [".", ".."].include?(clean.each_filename.first || ".")
    raise Invalid, "path #{path.inspect}: give a relative path inside the project" if invalid

    clean.to_s
  end

  def clean_source(file)
    source = (file[:source] || file["source"]).to_s
    raise Invalid, "source: at most #{MAX_BYTES} bytes a file" if source.bytesize > MAX_BYTES

    source.dup.force_encoding(Encoding::UTF_8).scrub
  end
end
