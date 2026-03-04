# frozen_string_literal: true

module Executor
  module Prompts
    YES_VALUES = %w[y yes].freeze
    NO_VALUES  = %w[n no].freeze

    module_function

    def confirm(message, default: true, input: $stdin, output: $stdout)
      suffix = default ? " [Y/n] " : " [y/N] "

      loop do
        output.print("#{message}#{suffix}")
        line = input.gets
        return default if line.nil?

        answer = line.strip.downcase
        return default if answer.empty?
        return true if YES_VALUES.include?(answer)
        return false if NO_VALUES.include?(answer)

        output.puts("Please answer yes or no.")
      end
    end

    def ask(message, default: nil, input: $stdin, output: $stdout)
      output.print("#{message}#{default ? " (#{default})" : ""}: ")
      line = input.gets
      return default if line.nil?

      answer = line.chomp
      answer.empty? ? default : answer
    end

    def read_file(path)
      File.read(path)
    rescue Errno::ENOENT, Errno::EACCES => e
      raise e.class, "Unable to read #{path}: #{e.message}"
    end
  end
end