# frozen_string_literal: true

require "time"
require_relative "../../trace/log"
require_relative "../../operator/services"
require_relative "../presentation_contract"

module Master
  module CLI
    module CommandRegistry
      module_function

      # /status — one frame of health, as dmesg lines. What is fine or does not
      # apply on this host says nothing: no "rcctl absent" on a Mac, no bundle row
      # when the bundle is satisfied, no raw bus events.
      #
      # `/status mission` and `/status runtime` read the two durable records a
      # frame does not show: the autonomous mission, and the known-good commit.
      def dispatch_status(root:, fix_loop:, bus:, git: Io::GitOperations.new(File.expand_path("..", root)), trace: nil,
                          learnings: nil, ctx: nil)
        word, rest = subcommand(ctx)
        return dispatch_mission(root, ctx: rest) if word == "mission"
        return dispatch_runtime(root, ctx: rest) if word == "runtime"
        return dispatch_services(ctx: rest) if word == "services"
        return dispatch_security if word == "security"

        gather_status_data(root:, fix_loop:, git:)
          .merge(rsi: rsi_opportunities(learnings))
          .then { |data| render_status_lines(data) }.join("\n")
      rescue StandardError => e
        "status0: #{e.message}"
      end

      def dispatch_services(ctx: nil)
        name, = subcommand(ctx)
        Master::Operator.status(name).map { |service, state| "service0: #{service} #{state}" }.join("\n")
      end

      def dispatch_security
        data = Master::Operator.security
        [
          "security0: constitution=#{data[:constitution]}",
          "cap0: profile=#{data[:capability_profile]} #{data[:capabilities].join(" ")}",
          "pledge0: openbsd=#{data[:openbsd_pledge]}",
          "patch0: transactional_fix=#{data[:transactional_fix]}",
          "model0: authority=#{data[:model_authority]}",
          "security0: monotonic_reduction=#{data[:monotonic_reduction]}",
          "mode0: observe=#{Master::Operator::Mode.summary(:observe)}",
          "mode0: plan=#{Master::Operator::Mode.summary(:plan)}",
          "mode0: repair=#{Master::Operator::Mode.summary(:repair)}",
          "mode0: deploy=#{Master::Operator::Mode.summary(:deploy)}",
        ].join("\n")
      end

      def gather_status_data(root:, fix_loop:, git:)
        {
          ahead_behind: git.ahead_behind, head: git.head || "?", dirty: git.dirty?("."), branch: git.branch || "?",
          svc: service_status,
          bg: fix_loop&.background_alive? ? "running" : "stopped",
          af: ENV["MASTER_AUTOFIX"] == "1" ? "on" : "off",
          bndl: bundle_status(File.expand_path("..", root)),
          failures: failure_events(root, 3),
          stage: last_event(root, "pipeline:stage_complete")&.dig("payload", "stage"),
          verdict: format_verdict(last_event(root, "review:verdict")),
          config: (Master::Ground::Config.new(root) rescue {})
        }
      end

      def render_status_lines(d)
        Master::CLI::PresentationContract.status_lines(
          d,
          verbose: ENV["MASTER_CLI_VERBOSE"] == "1" || ENV["MASTER_CLI_TRACE"] == "1",
        )
      end

      def git_line(d)
        ahead, behind = d[:ahead_behind]
        counts = [("#{ahead} ahead" if ahead.to_i.positive?), ("#{behind} behind" if behind.to_i.positive?)]
        return unless d[:branch]

        ["git0: #{d[:branch]} at #{d[:head]}", *counts.compact, d[:dirty] ? "dirty" : "clean"].join(", ")
      end

      # The feedback ledger's reading of the last week: a tool failing a fifth
      # of its calls, a correction or a provider error that keeps recurring.
      def rsi_opportunities(learnings)
        learnings.respond_to?(:opportunities) ? learnings.opportunities : []
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.rsi_opportunities")
        []
      end

      def format_opportunity(row)
        kind = row[:category].to_s.tr("_", " ")