module MASTER
  module CLI
    class Progress
      FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

      def initialize(message = "Processing")
        @message = message
        @frame = 0
        @running = false
        @thread = nil
      end

      def start
        return unless $stdout.tty?
        @running = true
        @thread = Thread.new do
          while @running
            print "\r#{FRAMES[@frame % FRAMES.length]} #{@message}..."
            $stdout.flush
            @frame += 1
            sleep 0.1
          end
          print "\r" + " " * (@message.length + 10) + "\r"
          $stdout.flush
        end
      end

      def stop
        @running = false
        @thread&.join
      end
    end

    class Timer
      def initialize
        @start_time = Time.now
      end

      def elapsed
        Time.now - @start_time
      end

      def format_elapsed
        seconds = elapsed
        if seconds < 1
          "#{(seconds * 1000).round}ms"
        elsif seconds < 60
          "#{seconds.round(2)}s"
        else
          minutes = (seconds / 60).floor
          secs = (seconds % 60).round
          "#{minutes}m #{secs}s"
        end
      end
    end
  end
end
