# frozen_string_literal: true

module Boot
  APP_NAMESPACE = Rails.application.class.module_parent_name
  DEFAULT_BANNER_WIDTH = 72

  SmokeTestResult = Struct.new(:ok, :messages, keyword_init: true)

  module_function

  def application_namespace
    APP_NAMESPACE
  end

  def banner(width: DEFAULT_BANNER_WIDTH)
    title = "#{application_namespace} Boot"
    line = "-" * width
    [line, title.center(width), line].join("\n")
  end

  def banner_with_web(web_url:, width: DEFAULT_BANNER_WIDTH)
    [banner(width: width), "Web: #{web_url}"].join("\n")
  end

  def smoke_test
    messages = check_database + check_cache
    ok = messages.none? { |msg| msg[:level] == :error }
    SmokeTestResult.new(ok: ok, messages: messages)
  end

  # Use when rendering a dashboard/list to avoid N+1 queries.
  def preload_for_dashboard(scope)
    scope.includes(:account, :profile)
  end

  def check_database
    ActiveRecord::Base.connection_pool.with_connection(&:active?)
    [{ level: :info, code: :database, message: "database ok" }]
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
    [{ level: :error, code: :database, message: e.message }]
  end

  def check_cache
    Rails.cache.write("boot_smoke_test", "1", expires_in: 1.second)
    return [{ level: :error, code: :cache, message: "cache read/write failed" }] unless Rails.cache.read("boot_smoke_test") == "1"

    [{ level: :info, code: :cache, message: "cache ok" }]
  rescue StandardError => e
    [{ level: :error, code: :cache, message: e.message }]
  end
end