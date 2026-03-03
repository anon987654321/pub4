# frozen_string_literal: true

module Boot
  TIME_FORMAT = "%Y-%m-%d %H:%M:%S UTC"
  BANNER_WIDTH = 72
  BANNER_INDENT = " " * 2

  class Runner
    def banner(app_name: default_app_name, now: Time.now.utc)
      timestamp = format_time(now)

      lines = [
        c("=" * BANNER_WIDTH, :cyan),
        c("#{BANNER_INDENT}#{app_name}", :green),
        c("#{BANNER_INDENT}Booting at #{timestamp}", :yellow),
        c("=" * BANNER_WIDTH, :cyan)
      ]

      lines.join("\n")
    end

    def smoke_test(models: default_models)
      return { ok: true, checks: [], errors: [] } unless rails_with_active_record?

      checks = []
      errors = []

      models.each do |model_config|
        result = run_smoke_check(model_config)
        checks << result
        errors << result[:error] if result[:error]
      end

      { ok: errors.empty?, checks:, errors: }
    end

    private

    def default_app_name
      return Rails.application.class.module_parent_name if defined?(Rails)

      "Application"
    end

    def rails_with_active_record?
      defined?(Rails) && defined?(ActiveRecord::Base)
    end

    def default_models
      return [] unless rails_with_active_record?

      [
        { name: "User", klass: safe_constantize("User"), includes: [:account], limit: 25 },
        { name: "Account", klass: safe_constantize("Account"), includes: [:users], limit: 25 }
      ].compact.select { |cfg| cfg[:klass] }
    end

    def run_smoke_check(model_config)
      model_name = model_config.fetch(:name)
      model_klass = model_config.fetch(:klass)
      includes_associations = Array(model_config[:includes])
      limit = model_config.fetch(:limit, 25)

      relation = model_klass.all
      relation = relation.includes(*includes_associations) unless includes_associations.empty?
      relation = relation.limit(limit)

      count = begin
        relation.count
      rescue ActiveRecord::StatementInvalid => e
        return { model: model_name, ok: false, count: 0, error: e.message }
      end

      { model: model_name, ok: true, count:, error: nil }
    end

    def safe_constantize(name)
      return name.safe_constantize if name.respond_to?(:safe_constantize)

      Object.const_get(name)
    rescue NameError
      nil
    end

    def format_time(time)
      time.strftime(TIME_FORMAT)
    end

    def c(text, color)
      return text unless colorize?

      color_method = color.to_sym
      "\e[#{ansi_code(color_method)}m#{text}\e[0m"
    end

    def colorize?
      $stdout.respond_to?(:tty?) && $stdout.tty?
    end

    def ansi_code(color)
      {
        cyan: 36,
        green: 32,
        yellow: 33,
        red: 31
      }.fetch(color, 0)
    end
  end
end