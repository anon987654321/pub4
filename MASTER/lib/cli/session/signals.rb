# frozen_string_literal: true

module Master
  module CLI
    class Session
      private

      def setup_signals
        trap("USR1") { on_usr1 }
        trap("INT")  { on_int }
      end

      def on_usr1
        Zeitwerk::Loader.for_gem.reload
        puts "\n#{@refs.renderer.render("reloaded", mode: :success)}"
      rescue StandardError => e
        puts "\n#{@refs.renderer.render("reload failed: #{e.message}", mode: :error)}"
      end

      def on_int
        if @pipeline_thread&.alive?
          @pipeline_thread.kill
          @pipeline_thread = nil
          puts "\n#{@refs.renderer.render("aborted", mode: :warning)}"
          return
        end
        if Time.now - @interrupt_at < 1
          @scan_thread&.kill
          @refs.session.save!
          exit(0)
        end

        @interrupt_at = Time.now
        puts "\n#{@refs.renderer.render("^C again to quit", mode: :warning)}"
      end
    end
  end
end
