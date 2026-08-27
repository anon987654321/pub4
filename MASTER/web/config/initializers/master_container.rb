# frozen_string_literal: true

Rails.application.config.x.master_start_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
Rails.application.config.x.master_container = nil
Rails.application.config.x.master_container_mutex = Mutex.new
Rails.application.config.x.master_bootstrap_started = false

Rails.application.config.after_initialize do
  MasterContainerLoader.warm_shared_namespace!
  MasterContainerLoader.rearm!
end

module MasterContainerLoader
  module_function

  # Master::Ground is loaded here, on the main thread, before the bootstrap
  # thread below exists.
  #
  # Master carries its own Zeitwerk loader and never eager-loads, so its
  # constants resolve by autoload on first reference. Zeitwerk autoloading is
  # not thread-safe, and the web tier arranges the one collision that matters:
  # ApplicationController names Master::Ground::Tool::Profile in its class body,
  # which Rails evaluates on the first request — inside the window where the
  # bootstrap thread is autoloading Master constants of its own. The collision
  # surfaces as `uninitialized constant Master::Ground::Tool::Profile`, and it
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

  # Arms the one bootstrap thread, and is safe to call on every request that
  # finds no container. The flag is claimed under the mutex so a burst of
  # requests during the ~40s boot starts one thread between them, not one each.
  #
  # ApplicationController#require_container! calls this. It used to be a stub
  # returning nil, on the grounds that the initializer owned the thread -- so
  # there was exactly one attempt per process and no way back from a lost one.
  def rearm!(config = Rails.application.config)
    return config.x.master_container if config.x.master_container

    claimed = config.x.master_container_mutex.synchronize do
      next false if config.x.master_bootstrap_started

      config.x.master_bootstrap_started = true
    end
    Thread.new { ensure! } if claimed
    nil
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
      Rails.logger.info("master_container: ready")
      container
    end
  # Exception, not StandardError. This runs in a thread with no joiner, so
  # anything it does not catch disappears without a line anywhere -- and the
  # flag above stays claimed, which used to mean the process served "Starting
  # up..." for the rest of its life having logged nothing. NoMemoryError is the
  # live case on a 1GB box under swap pressure, and it is not a StandardError.
  rescue Exception => e # rubocop:disable Lint/RescueException
    raise if e.is_a?(SystemExit) || e.is_a?(SignalException)

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
