# frozen_string_literal: true

module MASTER
  # ReviewGate -- every code-touching operation passes through here.
  #
  # Extracts file paths and inline code blocks from input + response text,
  # runs Scan.run(:quick) on each, and prints compact findings to stderr.
  # The original Result is returned unchanged -- display is a side effect.
  #
  # Usage (both paths converge here):
  #   ReviewGate.run(result, input: raw_user_input)
  module ReviewGate
    FILE_PATH_RE = %r{(?:^|\s|`|'|")([./~][\w./\-]+\.(?:rb|js|ts|py|go|sh|yml|yaml|json|md|erb|haml|css|scss|html))(?:\s|$|`|'|")}
    FENCE_RE     = /```(\w*)\n(.*?)```/m

    module_function

    def run(result, input: "")
      return result unless result.respond_to?(:ok?) && result.ok?
      return result if result.value.is_a?(Hash) && result.value[:handled]

      response_text = response_text_from(result)
      combined      = "#{input}\n#{response_text}"

      targets = real_file_targets(combined)
      blocks  = code_blocks(response_text)

      return result if targets.empty? && blocks.empty?

      findings = {}

      targets.each do |path|
        scan = Scan.run(path, depth: :quick) rescue nil
        next unless scan.is_a?(Hash) && scan[:total].to_i > 0

        scan[:by_file].each do |file, file_findings|
          findings[file] = file_findings unless file_findings.empty?
        end
      end

      blocks.each_with_index do |block, i|
        label    = "inline:#{i + 1}"
        detected = Review::ToolScanner.scan(block[:code], name: label) rescue []
        findings[label] = detected unless detected.empty?
      end

      display(findings) unless findings.empty?
      result
    end

    def real_file_targets(text)
      text.scan(FILE_PATH_RE)
          .flatten
          .map { |p| p.start_with?("~") ? File.expand_path(p) : File.expand_path(p, Dir.pwd) }
          .uniq
          .select { |p| File.exist?(p) }
    end

    def code_blocks(text)
      text.scan(FENCE_RE).map { |lang, code| { lang: lang, code: code } }
    end

    def display(findings)
      total = findings.values.sum(&:size)
      return if total == 0

      findings.each do |source, items|
        items.each do |f|
          $stderr.puts UI.dim("scan0: #{source}:#{f[:line]}  #{f[:rule]}  #{f[:message]}")
        end
      end
      $stderr.puts UI.dim("scan0: #{total} finding#{total == 1 ? '' : 's'}")
    end

    def response_text_from(result)
      v = result.value
      return "" unless v.is_a?(Hash)

      v[:rendered] || v[:response] || v[:answer] || ""
    end
  end
end
