# frozen_string_literal: true

module MASTER
  module Parser
    # Multi-language parser for shell scripts with embedded languages.
    # Handles .sh/.zsh/.bash scripts containing Ruby/Python heredocs.
    # Ported from MASTER v4 lib/parser/multi_language.rb — live dependency of evolve.rb.
    class MultiLanguage
      HEREDOC_PATTERNS = {
        ruby:   /<<-?(\w*RUBY\w*)\s*\n(.*?)\n\s*\1/m,
        python: /<<-?(\w*PYTHON\w*)\s*\n(.*?)\n\s*\1/m,
      }.freeze

      SHELL_EXTENSIONS = %w[.sh .zsh .bash].freeze
      SHELL_SHEBANGS    = %w[
        #!/bin/sh #!/bin/bash #!/bin/zsh
        #!/usr/bin/env sh #!/usr/bin/env bash #!/usr/bin/env zsh
      ].freeze

      attr_reader :file_path, :content

      def initialize(content = nil, file_path: nil)
        @content   = content
        @file_path = file_path
      end

      def self.parse_file(file_path)
        new(File.read(file_path), file_path: file_path).parse
      end

      def parse
        return { error: "No content to parse" } unless @content

        shell_script? ? parse_shell_script : { type: :unknown, content: @content }
      end

      def shell_script?
        return false unless @content

        SHELL_SHEBANGS.any? { |s| @content.start_with?(s) } ||
          (file_path && SHELL_EXTENSIONS.any? { |ext| file_path.end_with?(ext) })
      end

      # Reconstruct script with a modified heredoc block in-place.
      def replace_heredoc(original_block, new_code)
        @content.sub(original_block[:raw_block]) do
          "<<-#{original_block[:marker]}\n#{new_code}\n#{original_block[:marker]}"
        end
      end

      private

      def parse_shell_script
        result = { type: :shell, shell_code: @content, embedded: {}, language_blocks: [] }

        HEREDOC_PATTERNS.each do |lang, pattern|
          blocks = extract_heredocs(lang, pattern)
          result[:embedded][lang] = blocks unless blocks.empty?
          result[:language_blocks].concat(blocks)
        end

        result[:language_blocks].sort_by! { |b| b[:start_line] }
        result
      end

      def extract_heredocs(lang, pattern)
        blocks = []
        offset = 0

        @content.scan(pattern) do |match|
          marker = match[0]
          code   = match[1]

          match_start = @content.index(Regexp.last_match(0), offset)
          next unless match_start

          marker_line = @content[0...match_start].count("\n") + 1
          start_line  = marker_line + 1
          end_line    = start_line + code.count("\n")

          blocks << {
            language:  lang,
            code:      code,
            start_line: start_line,
            end_line:   end_line,
            marker:    marker,
            raw_block: Regexp.last_match(0),
          }

          offset = match_start + Regexp.last_match(0).length
        end

        blocks
      end
    end
  end
end
