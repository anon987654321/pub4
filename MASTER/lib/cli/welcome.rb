# frozen_string_literal: true

require "json"
require_relative "../io/exec"
require "time"

module Master
  module CLI
    # The first line an interactive session prints, before the boot that takes most of twenty seconds: the time,
    # how long since the last session and what it was about, and how many commits landed since. It reads the
    # stored session and git, so it is never the same sentence twice; the canned "hello — goal?" it replaces
    # said the same thing to everyone. Standard library only, because it runs before the bundle is activated.
    # Session#greet_from_model then has the model greet in its own words once the runtime is up.
    module Welcome
      module_function

      def line(root, now: Time.now)
        session = read_session(root)
        parts = [now.strftime("%H:%M")]
        last = session["ts"] && Time.at(session["ts"].to_i)
        parts << "last session #{ago(now - last)} ago#{topic(session)}" if last
        landed = last && commits_since(root, last)
        parts << "#{landed} #{landed == 1 ? "commit" : "commits"} since" if landed&.positive?
        parts.join(", ")
      end

      # What the model is told to greet from: the same facts, as plain context.
      def context(root, now: Time.now)
        session = read_session(root)
        last_user = Array(session["messages"]).reverse.find { |message| message["role"] == "user" }
        { time: now.strftime("%A %H:%M"), line: line(root, now:), last_message: last_user&.fetch("content", nil) }
      end

      def read_session(root)
        JSON.parse(File.read(File.join(root, ".master", "session.json")))
      rescue SystemCallError, JSON::ParserError # scan: intentional — no stored session is a first session
        {}
      end

      def topic(session)
        name = session["topic"] || session["name"]
        name ? " (#{name.to_s.strip[0, 48]})" : ""
      end

      def ago(seconds)
        minutes = (seconds / 60).round
        return "#{minutes}m" if minutes < 90

        hours = (minutes / 60.0).round
        hours < 48 ? "#{hours}h" : "#{(hours / 24.0).round}d"
      end

      def commits_since(root, time)
        since = "--since=#{time.iso8601}"

        out, status = Master::Io::Exec.capture2("git", "-C", root, "rev-list", "--count", since, "HEAD")
        status.success? ? out.to_i : nil
      rescue SystemCallError # scan: intentional — no git means no count, and the line leaves it out
        nil
      end
    end
  end
end

$stdout.write("welcome0: #{Master::CLI::Welcome.line(ARGV.fetch(0))}\n") if $PROGRAM_NAME == __FILE__
