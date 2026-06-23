# frozen_string_literal: true

Rails.application.config.x.master_start_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
Rails.application.config.x.master_container = nil
Rails.application.config.x.master_container_mutex = Mutex.new

module MasterContainerLoader
  module_function

  def ensure!(config = Rails.application.config)
    return config.x.master_container if config.x.master_container

    config.x.master_container_mutex.synchronize do
      return config.x.master_container if config.x.master_container

      root = Rails.root.join("..").to_s
      Master::Voice::TtsSupervisor.ensure_daemon!(root: root)
      container = Master.bootstrap_container(root: root)
      config.x.master_container = container
      start_scheduler(container)
      container
    end
  rescue StandardError => e
    Rails.logger.error("master_container boot failed: #{e.message}")
    nil
  end

  def start_scheduler(container)
    return if defined?(@scheduler_started) && @scheduler_started

    @scheduler_started = true
    Thread.new do
      sleep 300
      loop do
        due = container[:standing].due
        if due.any?
          results = container[:standing].run_due!
          results.each do |r|
            Master::Ground::Swallow.safe_call(context: "MasterContainerLoader.scheduler_publish", event_bus: container[:bus]) do
              container[:bus].publish("scheduler:ran", name: r[:name])
            end
          end
        end
        sleep 900
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "MasterContainerLoader.scheduler", event_bus: container[:bus])
      end
    end
  end
end