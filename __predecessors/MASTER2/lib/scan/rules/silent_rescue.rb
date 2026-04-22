# frozen_string_literal: true

class Scan::Rules::SilentRescue
  MESSAGE = "Silent rescue detected".freeze

  RESCUE_BLOCK_START = /^\s*rescue\b/.freeze
  RESCUE_MODIFIER = /\brescue\b/.freeze
  COMMENT_ONLY = /\A\s*(#.*)?\z/.freeze
  END_LIKE = /\A\s*(end|ensure|else|rescue)\b/.freeze

  def check(file, *_args)
    source = extract_source(file)
    return [] if source.nil? || source.empty?

    lines = source.lines
    findings = []
    findings.concat(find_silent_rescue_blocks(lines, file))
    findings.concat(find_modifier_rescues(lines, file))
    findings
  end

  private

  def extract_source(file)
    return file if file.is_a?(String)
    return file.source if file.respond_to?(:source)
    return file.content if file.respond_to?(:content)
    return file.read if file.respond_to?(:read)

    nil
  end

  def find_silent_rescue_blocks(lines, file)
    findings = []

    lines.each_with_index do |line, idx|
      next unless line.match?(RESCUE_BLOCK_START)
      next unless silent_rescue_line?(line)
      next unless rescue_body_empty?(lines, idx)

      findings << build_finding(file, idx + 1)
    end

    findings
  end

  def silent_rescue_line?(line)
    code = strip_inline_comment(line).strip
    return false unless code.start_with?("rescue")

    after = code.sub(/\Arescue\b/, "").strip
    after.empty? || after.match?(COMMENT_ONLY)
  end

  def rescue_body_empty?(lines, rescue_idx)
    i = rescue_idx + 1
    i += 1 while i < lines.length && blank_or_comment?(lines[i])
    i >= lines.length || lines[i].match?(END_LIKE)
  end

  def find_modifier_rescues(lines, file)
    findings = []

    lines.each_with_index do |line, idx|
      next unless line.match?(RESCUE_MODIFIER)
      next if line.lstrip.start_with?("rescue")
      next unless modifier_rescue_silent?(line)

      findings << build_finding(file, idx + 1)
    end

    findings
  end

  def modifier_rescue_silent?(line)
    stripped = strip_inline_comment(line)
    parts = stripped.split(/\brescue\b/, 2)
    return false if parts.length < 2

    rhs = parts.last.to_s.strip
    rhs.empty? || rhs == "nil"
  end

  def strip_inline_comment(line)
    line.sub(/\s+#.*\z/, "")
  end

  def blank_or_comment?(line)
    line.strip.empty? || line.lstrip.start_with?("#")
  end

  def build_finding(file, line_no)
    path = if file.respond_to?(:path)
             file.path
           elsif file.respond_to?(:filename)
             file.filename
           end

    { rule: self.class.name, message: MESSAGE, path: path, line: line_no }
  end
end