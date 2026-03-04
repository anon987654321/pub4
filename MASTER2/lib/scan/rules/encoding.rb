# frozen_string_literal: true

class Scan::Rules::Encoding < Scan::Rule
  NAME = "encoding"
  DESCRIPTION = "Detects non-UTF-8 encodings, BOM usage, and invalid UTF-8 content."

  UTF8_BOM = "\xEF\xBB\xBF".b.freeze
  MAGIC_ENCODING_REGEX = /
    \A \s* \# \s*
    (?:
      encoding \s* : \s* (?<enc1>[-\w]+) |
      -\*-\s* (?: coding|encoding ) \s* : \s* (?<enc2>[-\w]+) \s* -\*-
    )
  /ix.freeze

  SAMPLE_BYTES = 4096

  def check(path)
    data = read_sample(path)
    return [] if data.nil? || data.empty?

    issues = []
    issues << issue(path, "UTF-8 BOM detected; remove BOM.") if bom?(data)

    magic = magic_encoding(data)
    issues << issue(path, "Magic encoding comment specifies #{magic.inspect}; use UTF-8.") if magic && magic != "utf-8"

    issues << issue(path, "File contains invalid UTF-8 bytes.") if (magic.nil? || magic == "utf-8") && !valid_utf8?(data)

    issues
  end

  private

  def read_sample(path)
    File.open(path, "rb") { |f| f.read(SAMPLE_BYTES) }
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR
    nil
  end

  def bom?(data)
    data.bytesize >= 3 && data.start_with?(UTF8_BOM)
  end

  def magic_encoding(data)
    lines = data.lines.first(2)
    lines.each do |line|
      match = line.match(MAGIC_ENCODING_REGEX)
      next unless match

      enc = (match[:enc1] || match[:enc2]).to_s.downcase
      return enc unless enc.empty?
    end
    nil
  end

  def valid_utf8?(data)
    data.dup.force_encoding(Encoding::UTF_8).valid_encoding?
  end

  def issue(path, message)
    Scan::Issue.new(rule: NAME, path: path, message: message)
  end
end