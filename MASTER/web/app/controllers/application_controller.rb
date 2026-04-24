# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  @@container        = nil
  @@mutex            = Mutex.new
  @@start_ms         = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  @@scheduler_thread = nil

  private

  def container
    @@mutex.synchronize do
      @@container ||= Master.build(root: Rails.root.join("..").to_s).tap { |c| start_scheduler(c); Master.generate_boot_snapshot(c) rescue nil; c[:heartbeat]&.start! }
    end
  end

  def start_scheduler(c)
    return if @@scheduler_thread&.alive?
    @@scheduler_thread = Thread.new do
      sleep 300 # wait 5 min after boot before first check
      loop do
        begin
          due = c[:standing].due
          if due.any?
            results = c[:standing].run_due!
            results.each { |r| c[:bus].publish("scheduler:ran", name: r[:name]) rescue nil }
          end
        rescue StandardError
          # swallow — never crash the scheduler
        end
        sleep 900 # check every 15 min
      end
    end
    @@scheduler_thread.abort_on_exception = false
  end

  def start_ms
    @@start_ms
  end
end
