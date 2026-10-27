# frozen_string_literal: true

require_relative "../../lib/io/exec"

# Check-facing adapter for the shared bounded process runner.
#
# The :timeout sentinel is intentional: callers must distinguish a command that
# never completed from one that completed and returned a non-zero exit status.
module BoundedCommand
  DEFAULT_TIMEOUT_S = 30

  module_function

  def capture2e(*command, timeout: DEFAULT_TIMEOUT_S, **options)
    output, status = Master::Io::Exec.capture2e(
      *command, timeout:, raise_on_timeout: true, **options
    )

    [output, status]
  rescue Master::Io::Exec::TimeoutError => error
    output = Array(error.result).first.to_s
    output = "#{output}\n" unless output.empty? || output.end_with?("\n")
    label = command.find { |part| !part.is_a?(Hash) }.to_s
    [output + "TIMEOUT after #{timeout}s: #{label}", :timeout]
  rescue Errno::ENOENT, Errno::EACCES => error
    ["#{error.class}: #{error.message}", :timeout]
  end

  def timed_out?(status) = status == :timeout

  def success?(status) = !timed_out?(status) && status.success?
end
