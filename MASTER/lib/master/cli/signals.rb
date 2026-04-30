# frozen_string_literal: true

module Master
  class CLI
    private

    def setup_signals
      trap("USR1") do
        begin
          Zeitwerk::Loader.for_gem.reload
          puts "\n#{@renderer.render("reloaded", mode: :success)}"
        rescue StandardError => e
          puts "\n#{@renderer.render("reload failed: #{e.message}", mode: :error)}"
        end
      end
      trap("INT") do
        if Time.now - @interrupt_at < 1
          @scan_thread&.kill
          @session.save!
          exit(0)
        else
          @interrupt_at = Time.now
          puts "\n#{@renderer.render("^C again to quit", mode: :warning)}"
        end
      end
    end
  end
end
