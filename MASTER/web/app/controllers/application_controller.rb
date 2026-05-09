# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  @@container        = nil
  @@mutex            = Mutex.new
  @@start_ms         = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  @@scheduler_thread = nil

  private

  def visitor?
    request.env["master.tier"] != "authenticated"
  end
  helper_method :visitor? if respond_to?(:helper_method)

  def container
    @@mutex.synchronize do
      @@container ||= Master.bootstrap_container(root: Rails.root.join("..").to_s).tap do |c|
        start_scheduler(c)
      end
    end
  end

  def start_scheduler(c)
    return if @@scheduler_thread&.alive?
    @@scheduler_thread = Thread.new do
      sleep 300
      loop do
        begin
          due = c[:standing].due
          if due.any?
            results = c[:standing].run_due!
            results.each { |r| c[:bus].publish("scheduler:ran", name: r[:name]) rescue nil }
          end
        rescue StandardError
          nil
        end
        sleep 900
      end
    end
    @@scheduler_thread.abort_on_exception = false
  end

  def start_ms
    @@start_ms
  end
end
