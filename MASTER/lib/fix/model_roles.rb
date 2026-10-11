# frozen_string_literal: true

require "yaml"

module Master
  module Fix
    # Roles for the models in one /fix run. The council that critiques a render
    # must not be the model that edits the CSS, so each role resolves to its own
    # lane when an alternative is alive. Calls run one after another, never in
    # parallel: the claude lane is one subscription shared with other sessions.
    module ModelRoles
      ROLES = %i[critic fixer wisher].freeze
      DATA = File.expand_path("../../data/model_roles.yml", __dir__)
      CLI_BINARIES = { "claude-cli" => "claude", "grok-cli" => "grok" }.freeze

      Assignment = Data.define(:critic, :fixer, :wisher) do
        def shared? = critic && critic == fixer
      end

      module_function

      # The lane a model id travels: the text before ":" for CLI lanes, else the
      # vendor slug of an API id.
      def provider(model)
        id = model.to_s
        return id.split(":").first if id.include?(":")

        id.split("/").first.to_s
      end

      def config(path = DATA)
        YAML.safe_load_file(path, aliases: true) || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Fix::ModelRoles.config")
        {}
      end

      def assign(env: ENV, alive: method(:alive?), cfg: config)
        dead = Array(cfg["dead"]).map(&:to_s)
        usable = lambda do |role|
          Array(cfg.dig("roles", role.to_s)).map(&:to_s).select { |id| dead.none? { |d| id.start_with?(d) } && alive.call(id) }
        end
        pick = ->(role) { env["MASTER_FIX_#{role.upcase}_MODEL"].to_s.strip.then { |v| v.empty? ? nil : v } }

        fixer = pick.call(:fixer) || usable.call(:fixer).first
        critic = pick.call(:critic) || apart(usable.call(:critic), fixer) || fixer
        Assignment.new(critic:, fixer:, wisher: pick.call(:wisher) || usable.call(:wisher).first)
      end

      # A different provider first; a different model on the same lane second.
      def apart(candidates, fixer)
        candidates.find { |id| provider(id) != provider(fixer) } || candidates.find { |id| id != fixer }
      end

      def alive?(model)
        id = model.to_s
        return false if Master::Io::ModelQuota.over_quota?(id)

        binary = CLI_BINARIES[provider(id)]
        return on_path?(binary) if binary
        return Master.agy_cli_available? if provider(id) == "agy"

        true
      end

      def on_path?(binary)
        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
          exe = File.join(dir, binary)
          File.file?(exe) && File.executable?(exe)
        end
      end

      # The run's assignment, resolved and logged once at its start.
      def announce(assignment = assign)
        @current = assignment
        log_assignment(assignment)
        assignment
      end

      def current = @current ||= assign

      def log_assignment(assignment)
        Master::Trace::Dmesg.status("roles0", "critic=#{assignment.critic || "default"} fixer=#{assignment.fixer || "default"} wisher=#{assignment.wisher || "default"}")
        Master::Trace::Dmesg.status("roles0", "critic and fixer share #{assignment.fixer || "default routing"} (no alternative alive)") if assignment.shared? || assignment.fixer.nil?
      rescue StandardError, NameError
        nil
      end

      # Runs the block with the role's model pinned for this thread; no pin when
      # the role has no model or `only` is false.
      def pinned(role, only: true, &)
        model = only ? current.public_send(role) : nil
        Master::Review::LLMDispatcher::ModelPin.with(model, &)
      end
    end
  end
end
