# frozen_string_literal: true

Rails.application.config.x.master_start_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i

Rails.application.config.after_initialize do
  container = Master.bootstrap_container(root: Rails.root.join("..").to_s)
  Rails.application.config.x.master_container = container

  Thread.new do
    sleep 300
    loop do
      begin
        due = container[:standing].due
        if due.any?
          results = container[:standing].run_due!
          results.each { |r| container[:bus].publish("scheduler:ran", name: r[:name]) rescue nil }
        end
      rescue StandardError
        nil
      end
      sleep 900
    end
  rescue StandardError
    nil
  end
end
