# frozen_string_literal: true

module MASTER
  module Parser
    # Multi-language parser for shell scripts with embedded languages
    # Handles .sh/.zsh/.bash scripts containing Ruby/Python heredocs
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
          { type: :unknown, content: @content }
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

      # Parse shell script and extract embedded languages
      # @return [Hash] Structure with shell and embedded code blocks
      def parse_shell_script
        result = {
          type: :shell,
          shell_code: @content,
          embedded: {},
          language_blocks: []
        }

        # Extract heredocs for each language
        HEREDOC_PATTERNS.each do |lang, pattern|
          blocks = extract_heredocs(lang, pattern)
          result[:embedded][lang] = blocks unless blocks.empty?
          result[:language_blocks].concat(blocks)
        end

        # Sort language blocks by line number
        result[:language_blocks].sort_by! { |block| block[:start_line] }

        result
      end

      # Extract heredoc blocks for a specific language
      # @param lang [Symbol] Language identifier (:ruby, :python)
      # @param pattern [Regexp] Pattern to match heredocs
      # @return [Array<Hash>] Array of extracted code blocks with metadata
      def extract_heredocs(lang, pattern)
        blocks = []
        offset = 0

        @content.scan(pattern) do |match|
          marker = match[0]
          code = match[1]
          
          # Find the position of this match
          match_start = @content.index(Regexp.last_match(0), offset)
          next unless match_start

          # Calculate line number
          start_line = @content[0...match_start].count("\n") + 1
          end_line = start_line + code.count("\n")

          blocks << {
            language: lang,
            code: code,
            start_line: start_line,
            end_line: end_line,
            marker: marker,
            raw_block: Regexp.last_match(0)
          }

          offset = match_start + Regexp.last_match(0).length
        end

        blocks
      end

      # Extract shell-only code (without heredocs)
      # @return [String] Shell code with heredocs removed
      def extract_shell_code
        result = @content.dup

        HEREDOC_PATTERNS.each_value do |pattern|
          result = result.gsub(pattern, '# [heredoc removed]')
        end

        result
      end

      # Reconstruct script with modified heredoc
      # @param original_block [Hash] Original block metadata
      # @param new_code [String] New code to replace block
      # @return [String] Modified script content
      def replace_heredoc(original_block, new_code)
        @content.sub(original_block[:raw_block]) do
          "<<-#{original_block[:marker]}\n#{new_code}\n#{original_block[:marker]}"
        end
      end
    end
  end
end
