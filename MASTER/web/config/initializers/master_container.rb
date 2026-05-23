# frozen_string_literal: true

Rails.application.config.x.master_start_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i

Rails.application.config.after_initialize do
  container = Master.bootstrap_container(root: Rails.root.join("..").to_s)
  Rails.application.config.x.master_container = container

  # Tighten perms on secret/data files; ignore if absent.
  Dir.glob(Rails.root.join("storage", "*.sqlite3")).each { |p| File.chmod(0o640, p) rescue nil }
  secret = Rails.root.join("tmp", "local_secret.txt")
  File.chmod(0o600, secret) if File.exist?(secret)

  Thread.new do
    sleep 300
    loop do
      begin
        due = container[:standing].due
        if due.any?
          results = container[:standing].run_due!
          results.each { |r| container[:bus].publish("scheduler:ran", name: r[:name]) rescue nil }
        end
      rescue StandardError => _e
        nil
      end
      sleep 900
    end
  rescue StandardError => _e
    nil
  end
end
