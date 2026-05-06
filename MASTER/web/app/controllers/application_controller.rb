# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../../lib", __FILE__)
require "master"

class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :authenticate!

  @@container        = nil
  @@mutex            = Mutex.new
  @@start_ms         = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  @@scheduler_thread = nil

  private

  def authenticate!
    return if request.path == "/up" || request.path == "/health"
    if session[:tier] == "authenticated"
      return
    end
    tok = web_token
    if params[:token] == tok || request.headers["X-Token"] == tok
      session[:tier] = "authenticated"
      return
    end
    session[:tier] ||= "visitor"
  end

  def visitor?
    session[:tier] != "authenticated"
  end
  helper_method :visitor? if respond_to?(:helper_method)

  def web_token
    cfg_file = File.join(Rails.root, "../.master/config.yml")
    cfg = YAML.safe_load_file(cfg_file, permitted_classes: [], aliases: true) rescue {}
    cfg["web_token"].presence || generate_token!(cfg_file, cfg)
  end

  def generate_token!(cfg_file, cfg)
    require "securerandom"
    tok = SecureRandom.urlsafe_base64(24)
    cfg["web_token"] = tok
    File.write(cfg_file, cfg.to_yaml)
    tok
  end

  def container
    @@mutex.synchronize do
      @@container ||= Master.build(root: Rails.root.join("..").to_s).tap do |c|
        start_scheduler(c)
        Master.generate_boot_snapshot(c) rescue nil
        c[:heartbeat]&.start!
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
