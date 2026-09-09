# frozen_string_literal: true

require_relative "../command_registry/formatter"

module Master
  module CLI
    class Session
      private

      def run_undo = report_undo("undo", @refs.undo.undo!)

      def report_undo(verb, res)
        return puts @refs.renderer.render(res.message, mode: :warning) unless res.is_a?(Master::Result) && res.ok?

        puts @refs.renderer.render("#{verb}: #{Array(res.value!).join(", ")}", mode: :success)
      end

      def toggle_focus
        @focus_mode = !@focus_mode
        puts @refs.renderer.render("focus: #{@focus_mode ? "on" : "off"}", mode: :dim)
      end

      def run_sound_critique = run_critique(:sound, label: "sound-critique", intro: "assembling audio panel")
      def run_critique(mode, label:, intro:)
        puts @refs.renderer.render("#{label}: #{intro}", mode: :dim)
        critic = Master::Review::Council::Critique.new(mode:, agent: @refs.agent, event_bus: @refs.bus)
        result = critic.run
        unless result.ok?
          puts @refs.renderer.render("#{label}: #{result.message}", mode: :warning)
          return
        end
        data = result.value!
        if data[:metrics]
          puts @refs.renderer.render("#{label}: #{data[:metrics].to_s.lines.first}", mode: :dim)
        end
        picks = data[:cherry_picks]
        puts @refs.renderer.render("#{label}: #{picks.size} cherry-pick(s)", mode: :dim)
        picks.each { |p| puts @refs.renderer.render("  cherry: #{p}", mode: :dim) }
        data[:feedback].each do |f|
          puts @refs.renderer.render("  [#{f[:persona]}] #{f[:feedback].to_s.lines.first.to_s.strip}", mode: :dim)
        end
      end
    end
  end
end
