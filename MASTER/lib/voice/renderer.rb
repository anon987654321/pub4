# frozen_string_literal: true
# encoding: utf-8

require "pastel"
require "socket"
require_relative "../ground/host_budget"
require_relative "aesthetic"
require_relative "strunk_pass"
require_relative "renderer/git_status"
require_relative "renderer/system_info"
require_relative "renderer/text_formatting"

module Master
  module Voice
    DEFAULT_WEB_PORT = Ground::Config::DEFAULT_WEB_PORT

    class Renderer
      BOOT_DMESG_LINES = 10
      MS_PER_SEC = 1000

      include GitStatus
      include SystemInfo
      include PromptComponents
      include TextFormatting

      def initialize(config:)
        @config = config
        @p = Pastel.new
        @boot_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * MS_PER_SEC).to_i
      end

      def session_line(name)
        @p.dim("session0: ") + @p.dim.underline(name.to_s.downcase)
      end

      def uptime
        seconds = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * MS_PER_SEC).to_i - @boot_ms) / MS_PER_SEC
        hours, remainder = seconds.divmod(3600)
        minutes, = remainder.divmod(60)
        hours.positive? ? "up #{hours}h#{minutes}m" : "up #{minutes}m"
      end

      def boot_wayfinding(constitution:, agent:, scan:)
        parts = ["constitution #{constitution ? "ok" : "pending"}", "agent #{agent ? "ok" : "pending"}"]
        parts << { done: "scan ok", active: "scan active" }.fetch(scan, "scan pending")
        d("boot0: #{parts.join(", ")}")
      end

      def render(content, mode: :plain)
        context = output_context(mode)
        text = output_guard.sanitize(beautify(content.to_s), context:)
        # Conversational output only: strip the padding a terse reply does not
        # need, leaving diagnostic and dmesg output whole. MASTER_BREVITY=0 opts
        # out if the strip ever eats something that mattered.
        text = StrunkPass.brevity(text) if context == :routine && ENV["MASTER_BREVITY"] != "0"
        case mode
        when :error then @p.red("err: #{text}")
        when :success then @p.bright_red("ok: #{text}")
        when :warning then @p.red("warn: #{text}")
        when :dim then @p.dim(text)
        when :dmesg then format_dmesg(text)
        else text
        end
      end

      def closing
        lines = (Master.load_yaml(Master.data_path("patterns.yml")) || {})["closings"]
        return unless lines.is_a?(Array) && lines.any?

        @p.dim(lines.sample)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "renderer.closing")
        nil
      end

      def output_guard
        @output_guard ||= Master::Voice::OutputGuard.new
      end

      def output_context(mode)
        return :diagnostic if %i[dmesg diag error].include?(mode)
        return :completion if mode == :success

        :routine
      end

      private

      def d(text) = @p.dim(text)
    end
  end
end
