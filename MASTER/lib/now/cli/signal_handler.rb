# frozen_string_literal: true

module Master
  module Now
    class CLI
      class SignalHandler
        def initialize(cli:)
          @cli = cli
        end

        def install!
          trap("USR1") { on_usr1 }
          trap("INT")  { on_int }
        end

        private

        def on_usr1
          Zeitwerk::Loader.for_gem.reload
          puts "\n#{@cli.renderer.render("reloaded", mode: :success)}"
        rescue StandardError => e
          puts "\n#{@cli.renderer.render("reload failed: #{e.message}", mode: :error)}"
        end

        def on_int
          thread = @cli.instance_variable_get(:@pipeline_thread)
          if thread&.alive?
            thread.kill
            @cli.instance_variable_set(:@pipeline_thread, nil)
            puts "\n#{@cli.renderer.render("aborted", mode: :warning)}"
            return
          end
          interrupt_at = @cli.instance_variable_get(:@interrupt_at)
          if Time.now - interrupt_at < 1
            @cli.instance_variable_get(:@bg_thread)&.kill
            @cli.session.save!
            puts "\n"
            exit(0)
          else
            @cli.instance_variable_set(:@interrupt_at, Time.now)
            puts "\n#{@cli.renderer.render("^C again to quit", mode: :warning)}"
          end
        end
      end
    end
  end
end