# frozen_string_literal: true

module MASTER
  module Parser
    # Multi-language parser for shell scripts with embedded languages
    # Handles .sh/.zsh/.bash scripts containing Ruby/Python heredocs
    # Standalone stub implementation for MASTER2
    class MultiLanguage
      HEREDOC_PATTERNS = {
        ruby: /<<-?(\w*RUBY\w*)\s*\n(.*?)\n\s*\1/m,
        python: /<<-?(\w*PYTHON\w*)\s*\n(.*?)\n\s*\1/m,
      }.freeze

      SHELL_EXTENSIONS = %w[.sh .zsh .bash].freeze
      SHELL_SHEBANGS = %w[#!/bin/sh #!/bin/bash #!/bin/zsh #!/usr/bin/env sh #!/usr/bin/env bash #!/usr/bin/env zsh].freeze

      attr_reader :file_path, :content

      def initialize(content = nil, file_path: nil)
        @content = content
        @file_path = file_path
      end

      # Parse a file and extract multi-language contexts
      # @param file_path [String] Path to file to parse
      # @return [Hash] Parsed structure with shell and embedded languages
      def self.parse_file(file_path)
        content = File.read(file_path)
        new(content, file_path: file_path).parse
      end

      # Parse content and extract multi-language contexts
      # @return [Hash] Structure with shell code and embedded languages
      def parse
        return { error: "No content to parse" } unless @content

        if shell_script?
          parse_shell_script
        else
          detect_language_by_extension
        end
      end

      # Check if content is a shell script
      # @return [Boolean] true if content appears to be a shell script
      def shell_script?
        return false unless @content

        # Check by shebang
        return true if SHELL_SHEBANGS.any? { |shebang| @content.start_with?(shebang) }

        # Check by file extension
        return true if @file_path && SHELL_EXTENSIONS.any? { |ext| @file_path.end_with?(ext) }

        false
      end

      private

      def parse_shell_script
        result = { type: :shell, content: @content, embedded: [] }

        HEREDOC_PATTERNS.each do |lang, pattern|
          @content.scan(pattern) do |match|
            result[:embedded] << { language: lang, content: match[1] }
          end
        end

        result
      end

      def detect_language_by_extension
        return { type: :unknown, content: @content } unless @file_path

        ext = File.extname(@file_path)
        lang = case ext
               when '.rb' then :ruby
               when '.py' then :python
               when '.js' then :javascript
               when '.ts' then :typescript
               when '.go' then :go
               when '.rs' then :rust
               else :unknown
               end

        { type: lang, content: @content }
      end
    end
  end
end
