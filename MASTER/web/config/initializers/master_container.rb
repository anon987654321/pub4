# frozen_string_literal: true

Rails.application.config.x.master_start_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
Rails.application.config.x.master_container = nil
Rails.application.config.x.master_container_mutex = Mutex.new
Rails.application.config.x.master_bootstrap_started = false

Rails.application.config.after_initialize do
  next if Rails.application.config.x.master_bootstrap_started

  Rails.application.config.x.master_bootstrap_started = true
  MasterContainerLoader.warm_shared_namespace!
  Thread.new { MasterContainerLoader.ensure! }
end

module MasterContainerLoader
  module_function

  # Master::Ground is loaded here, on the main thread, before the bootstrap
  # thread below exists.
  #
  # Master carries its own Zeitwerk loader and never eager-loads, so its
  # constants resolve by autoload on first reference. Zeitwerk autoloading is
  # not thread-safe, and the web tier arranges the one collision that matters:
  # ApplicationController names Master::Ground::ToolProfile in its class body,
  # which Rails evaluates on the first request — inside the window where the
  # bootstrap thread is autoloading Master constants of its own. The collision
  # surfaces as `uninitialized constant Master::Ground::ToolProfile`, and it
  # takes out any request that lands in the window, including a warming probe.
  #
  # 160 ms for the namespace, once, against a container bootstrap measured in
  # seconds. Eager-loading all of Master would cost 941 ms and delay /up, which
  # is the thing the bootstrap thread exists to avoid.
  def warm_shared_namespace!
    Master::LOADER.eager_load_namespace(Master::Ground)
  rescue StandardError => e
    Rails.logger.warn("master_container: could not warm Master::Ground: #{e.class}: #{e.message}")
  end

  def ensure!(config = Rails.application.config)
    return config.x.master_container if config.x.master_container

    config.x.master_container_mutex.synchronize do
      return config.x.master_container if config.x.master_container

      root = Rails.root.join("..").to_s
      Master.prepare_runtime!
      Master::Voice::TtsSupervisor.ensure_daemon!(root:)
      TtsJob.ensure_worker!
      container = Master.bootstrap_container(root:)
      config.x.master_container = container
      start_scheduler(container)
      container
    end
  rescue StandardError => e
    Rails.logger.error("master_container boot failed: #{e.class}: #{e.message}")
    config.x.master_bootstrap_started = false
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
