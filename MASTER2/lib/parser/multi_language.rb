# frozen_string_literal: true

module Parser
  class MultiLanguage
    HEREDOC_START = /<<[-~]?(['"]?)([A-Za-z_]\w*)\1/.freeze

    def initialize(language_registry, default_language: nil)
      @language_registry = language_registry
      @default_language = default_language
    end

    def parse(source_code, language_name, filename: nil)
      language = resolve_language(language_name || @default_language, filename: filename)
      sanitized_source, heredocs = extract_heredocs(source_code)

      {
        language: language,
        source: sanitized_source,
        heredocs: heredocs
      }
    end

    def extract_heredocs(source_code)
      heredocs = []
      sanitized = +""
      index = 0

      while (match = HEREDOC_START.match(source_code, index))
        sanitized << source_code[index...match.begin(0)]
        heredocs << read_heredoc(source_code, match.end(0), match[2])
        index = heredocs[-1][:end_index]
        sanitized << match[0]
      end

      sanitized << source_code[index..] if index < source_code.length
      [sanitized, heredocs]
    end

    private

    def resolve_language(language_name, filename:)
      return @language_registry.fetch(language_name) if language_name

      inferred = filename && @language_registry.infer_from_filename(filename)
      inferred || @language_registry.default
    end

    def read_heredoc(source_code, content_start_index, terminator)
      terminator_regex = /^[ \t]*#{Regexp.escape(terminator)}\r?\n/

      terminator_match = source_code.match(terminator_regex, content_start_index)
      content_end_index = terminator_match ? terminator_match.begin(0) : source_code.length

      {
        terminator: terminator,
        content: source_code[content_start_index...content_end_index],
        start_index: content_start_index,
        end_index: terminator_match ? terminator_match.end(0) : source_code.length
      }
    end
  end
end