# frozen_string_literal: true

require "open3"
require "timeout"

module Master
  module Review
    class LLMDispatcher
      # The lanes that are a program on this machine rather than an endpoint:
      # Claude Code and Antigravity. Each runs through a slot, so four sessions
      # cannot open four of them, and each refuses outright where its binary is
      # not installed.
      module CliSender
        private

        def send_agy_cli(model_alias, messages, sys:, stream: false, &blk)
          agy_bin = find_agy_bin
          return Result.err("agy: no agy on PATH", category: :no_api_key) unless agy_bin

          agy_cli_call(agy_bin, model_alias, messages, sys, stream, &blk)
        end

        def agy_cli_call(agy_bin, model_alias, messages, sys, stream, &blk)
          CLI_SLOTS.pop
          prompt = text_prompt_for(messages)
          full_prompt = sys && !sys.empty? ? "#{sys}\n\n---\n\n#{prompt}" : prompt
          args = [agy_bin, "-p", full_prompt, "--output-format", "text"]
          if model_alias && !model_alias.empty? && model_alias != "auto" && model_alias != "agy"
            args += ["--model", model_alias]
          end
          timeout_s = agy_cli_timeout_s
          out, err, status = capture3_with_timeout(timeout_s, *args)
          return Result.err("agy: #{err.strip}", category: :provider_error) unless status.success?
          res = out.strip
          blk&.call(res) if stream && block_given?
          Result.ok(res)
        rescue Timeout::Error
          Result.err("agy: timed out after #{timeout_s}s", category: :timeout)
        rescue StandardError => e
          Result.err("agy: #{e.message}", category: :provider_error)
        ensure
          CLI_SLOTS << true
        end

        # The same reading of PATH that ModelRouter uses to keep an absent lane
        # out of a chain, here so a dispatch reached any other way refuses too.
        # MASTER_NO_CLAUDE_CLI=1 takes the lane out on a box that has the binary.
        def claude_on_path?
          return false if ENV["MASTER_NO_CLAUDE_CLI"] == "1"
          return @claude_on_path unless @claude_on_path.nil?

          @claude_on_path = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
            exe = File.join(dir, "claude")
            File.file?(exe) && File.executable?(exe)
          end
        end

        def find_agy_bin
          if ENV["AGY_BIN"] && File.file?(ENV["AGY_BIN"]) && File.executable?(ENV["AGY_BIN"])
            return ENV["AGY_BIN"]
          end
          home_bin = File.expand_path("~/.local/bin/agy")
          return home_bin if File.file?(home_bin) && File.executable?(home_bin)

          ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
            candidate = File.join(dir, "agy")
            return candidate if File.file?(candidate) && File.executable?(candidate)
          end
          "agy"
        end

        def agy_cli_timeout_s
          Integer(ENV.fetch("MASTER_AGY_CLI_TIMEOUT", AGY_CLI_TIMEOUT_S.to_s))
        rescue ArgumentError
          AGY_CLI_TIMEOUT_S
        end

        # A lane whose binary is absent fails with ENOENT, which reads as a
        # retriable provider_error, so the chain sleeps through a backoff on a
        # lane that cannot answer at all, and a scan pays that on every file.
        # Absent is permanent, so the chain walks on at once.
        def send_claude_cli(model_alias, messages, sys:)
          return Result.err("claude-cli: no claude on PATH", category: :no_api_key) unless claude_on_path?

          claude_cli_call(model_alias, messages, sys)
        end

        # The slot is taken and returned here, so a lane refused above never
        # returns one it did not take and leaves the queue as it found it.
        def claude_cli_call(model_alias, messages, sys)
          CLI_SLOTS.pop
          args = ["claude", "--print", "--model", model_alias]
          args += ["--system-prompt", sys] if sys && !sys.empty?
          timeout_s = claude_cli_timeout_s
          out, err, status = capture3_with_timeout(timeout_s, *args, stdin_data: text_prompt_for(messages))
          return Result.err("claude-cli: #{err.strip}", category: :provider_error) unless status.success?
          Result.ok(out.strip)
        rescue Timeout::Error
          Result.err("claude-cli: timed out after #{timeout_s}s", category: :timeout)
        rescue StandardError => e
          Result.err("claude-cli: #{e.message}", category: :provider_error)
        ensure
          CLI_SLOTS << true
        end

        def capture3_with_timeout(timeout_s, *cmd, stdin_data: nil)
          Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
            stdin.write(stdin_data) if stdin_data
            stdin.close
            out_reader = Thread.new { stdout.read }
            err_reader = Thread.new { stderr.read }
            if wait_thr.join(timeout_s)
              [out_reader.value, err_reader.value, wait_thr.value]
            else
              terminate_subprocess(wait_thr)
              # Kill the readers before closing what they are reading. Closing
              # first left both threads inside IO#read on a closed handle, so each
              # terminated with "stream closed in another thread" and
              # report_on_exception printed a backtrace over the operator's
              # prompt — twice, on every timeout.
              [out_reader, err_reader].each { |reader| reader.kill.join }
              [stdout, stderr].each { |io| io.close unless io.closed? }
              raise Timeout::Error
            end
          end
        end

        def claude_cli_timeout_s
          Integer(ENV.fetch("MASTER_CLAUDE_CLI_TIMEOUT", CLAUDE_CLI_TIMEOUT_S.to_s))
        rescue ArgumentError
          CLAUDE_CLI_TIMEOUT_S
        end
      end
    end
  end
end
