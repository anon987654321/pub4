# frozen_string_literal: true

require "fileutils"

module Operator
  # Operator output in OpenBSD's dmesg grammar: `unitN at parent: detail`, one
  # line per fact. MASTER/lib/trace/dmesg.rb speaks the same shape; this copy
  # exists because bin/ci runs from a copy-tree on vm23 with no MASTER beside it,
  # and the gate runner and the deploy scripts read it from here.
  module Dmesg
    ANSI = /\e\[[0-9;?]*[A-Za-z]/
    # A line naming a file position or a verdict. Minitest's `[test/x.rb:12]`,
    # RuboCop's `app/x.rb:3:5: C:`, the design lints' `lint: file:line …` and
    # every summary that counts failures or offences all carry one of the two.
    VERDICT = /\b(?:fail(?:ed|ures?)?|errors?|offen[cs]es?|violations?|exceed(?:s|ed)?|missing|expected|refused)\b/i
    FINDING = Regexp.union(/:\d+\b/, VERDICT)
    FINDING_LIMIT = 8

    module_function

    def line(unit, parent, detail) = "#{unit} at #{parent}: #{detail}"

    # Escapes are for a person at a terminal who has not asked for none.
    def escapes?(io = $stdout, env = ENV) = io.tty? && env["NO_COLOR"].to_s.empty?

    def plain(text) = text.to_s.scrub.gsub(ANSI, "").delete("\r")

    # Identical consecutive lines print once, with a count.
    def collapse(lines)
      lines.map(&:chomp).chunk_while { |a, b| a == b }.map do |run|
        run.size > 1 ? "#{run.first} ×#{run.size}" : run.first
      end
    end

    def duration(seconds)
      return format("%.1fs", seconds) if seconds < 60

      minutes, rest = seconds.round.divmod(60)
      "#{minutes}m #{rest}s"
    end

    # The lines of a failed command's output worth a person's first look: the
    # ones naming a position or a verdict, or its last lines when none does —
    # a test run killed mid-suite prints dots and nothing else.
    def findings(text, limit: FINDING_LIMIT)
      lines = collapse(plain(text).lines).reject { |candidate| candidate.strip.empty? }
      hits = lines.grep(FINDING)
      picked = hits.empty? ? lines.last(limit) : hits.first(limit)
      picked.map { |finding| finding.strip[0, 200] }
    end

    # bin/ci's runner, in place of ActiveSupport::ContinuousIntegration.
    #
    # Rails' runner prints every step's banner, command and output, then an
    # emoji verdict, all in raw ANSI whether or not anyone is at a terminal, so
    # a green run on vm23 puts hundreds of lines into ~/vps-deploy.log and a red
    # one hides its cause among them. This one writes each step's output to a log
    # file and prints only what a person acts on: a failed step with its first
    # findings, a `warn:` line a passing step raised, and one summary.
    #
    # The DSL and the exit status are Rails': `step title, *command` inside the
    # block, every step runs, and the process exits 1 when any step failed.
    class CiRun
      Result = Struct.new(:title, :ok, :seconds, keyword_init: true)
      UNIT = "ci0"
      WARN = /\Awarn: /

      def self.run(app, log: ENV.fetch("PUB4_CI_LOG", File.join("log", "ci.log")), out: $stdout, &steps)
        ENV["CI"] = "true"
        ci = new(app, log:, out:)
        ci.perform(&steps)
        exit 1 unless ci.success?
        ci
      end

      attr_reader :results

      def initialize(app, log:, out:)
        @app = app
        @out = out
        @results = []
        @log_path = log
        @log = open_log(log)
      end

      def perform(&steps)
        started = clock
        Signal.trap("INT") { say("interrupted during #{@current}"); exit 1 }
        instance_eval(&steps)
        summarize(clock - started)
        self
      ensure
        Signal.trap("INT", "DEFAULT")
        @log&.close
      end

      def success? = results.all?(&:ok)

      def step(title, *command)
        @current = title
        progress("running #{title}")
        @log&.puts Dmesg.line(UNIT, @app, "#{title}: #{command.join(' ')}")
        from = log_size
        started = clock
        ok = @log ? system(*command, out: @log, err: @log) : system(*command)
        seconds = clock - started
        results << Result.new(title:, ok: ok == true, seconds:)
        ok == true ? raise_warnings(title, from) : report_failure(title, seconds, from)
      end

      private

      def raise_warnings(title, from)
        step_output(from).lines.grep(WARN).each { |warning| say("#{title} #{warning.chomp}") }
      end

      def report_failure(title, seconds, from)
        say("#{title} failed in #{Dmesg.duration(seconds)}")
        Dmesg.findings(step_output(from)).each { |finding| @out.puts "  #{finding}" }
      end

      def summarize(seconds)
        failed = results.reject(&:ok).map(&:title)
        summary = "#{results.count(&:ok)} of #{results.size} steps passed in #{Dmesg.duration(seconds)}"
        summary += "; #{failed.join(', ')} failed" unless failed.empty?
        say(summary)
        say("step output in #{File.expand_path(@log_path)}") if @log && !failed.empty?
      end

      # CI uses the same append-only dmesg stream as every other operator
      # surface. Scrollback is the record; never repaint a line.
      def progress(text)
        say(text)
      end

      def say(text)
        @out.puts Dmesg.line(UNIT, @app, text)
      end

      # A log that cannot be written is not a reason to lose step output: the
      # run says so once and lets each command print where it stands.
      def open_log(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "w").tap { |file| file.sync = true }
      rescue SystemCallError => e
        say("#{path} unwritable (#{e.class}), step output follows inline")
        nil
      end

      def log_size = @log ? File.size(@log_path) : 0

      def step_output(from)
        return "" unless @log

        File.binread(@log_path, File.size(@log_path) - from, from).to_s
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

# The deploy scripts are zsh and read the same two rules from here rather than
# restating them: `ruby dmesg.rb collapse < output` and
# `ruby dmesg.rb findings < output`.
if $PROGRAM_NAME == __FILE__
  text = $stdin.read.to_s
  case ARGV.first
  when "collapse" then puts Operator::Dmesg.collapse(Operator::Dmesg.plain(text).lines)
  when "findings" then puts Operator::Dmesg.findings(text)
  else abort "usage: ruby #{File.basename(__FILE__)} collapse|findings < output"
  end
end
