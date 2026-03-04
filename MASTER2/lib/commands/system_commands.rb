# frozen_string_literal: true

module Commands
  class SystemCommands
    DEFAULT_PAGE_SIZE = 50
    MAX_ARGUMENTS = 10
    DEFAULT_SEPARATOR = /\s+/
    RECENT_ACTIVITY_DAYS = 30

    def initialize(current_user:, args: nil)
      @current_user = current_user
      @args = args
    end

    def build_help
      command_names = available_command_names
      [
        "Available system commands:",
        command_names.map { |name| "  - #{name}" }
      ].flatten.join("\n")
    end

    def build_user_report
      require_admin!

      options = parse_options(@args)
      page_size = options.fetch(:page_size, DEFAULT_PAGE_SIZE)

      users = fetch_users_for_report(options)
      paged_users = users.limit(page_size)

      {
        users: paged_users.map { |user| serialize_user_report_row(user) },
        total: users.count,
        page_size: page_size
      }
    end

    def scan_inactive_users
      require_admin!

      options = parse_options(@args)
      cutoff_time = options.fetch(:cutoff_time, RECENT_ACTIVITY_DAYS.days.ago)

      inactive_users = User
        .includes(:profile)
        .where("last_sign_in_at IS NULL OR last_sign_in_at < ?", cutoff_time)
        .order(:id)

      {
        cutoff_time: cutoff_time,
        count: inactive_users.count,
        users: inactive_users.limit(DEFAULT_PAGE_SIZE).map { |user| serialize_user_report_row(user) }
      }
    end

    def enforce_maintenance_mode
      require_admin!

      options = parse_options(@args)
      enabled = options.fetch(:enabled, true)

      maintenance_setting = SystemSetting.find_or_initialize_by(key: "maintenance_mode")
      maintenance_setting.value = enabled.to_s
      maintenance_setting.save!

      { maintenance_mode: enabled }
    end

    def build_system_settings
      require_admin!

      settings = SystemSetting.order(:key)
      { settings: settings.map { |setting| serialize_setting(setting) } }
    end

    private

    attr_reader :current_user, :args

    def available_command_names
      public_methods(false)
        .grep(/\A(build|scan|enforce)_/)
        .map(&:to_s)
        .sort
    end

    def require_admin!
      return if current_user&.admin?

      raise SecurityError, "Admin privileges are required to run this command"
    end

    def parse_options(raw_args)
      tokens = tokenize_args(raw_args)
      options = {}

      tokens.each do |token|
        key, value = token.split("=", 2)
        next unless key

        normalized_key = key.to_s.strip.downcase.to_sym
        normalized_value = value.nil? ? true : coerce_value(value)

        options[normalized_key] = normalized_value
      end

      options
    end

    def tokenize_args(raw_args)
      raw_text = raw_args.to_s.strip
      return [] if raw_text.empty?

      raw_text.split(DEFAULT_SEPARATOR, MAX_ARGUMENTS)
    end

    def coerce_value(value)
      stripped = value.to_s.strip
      return true if stripped.casecmp("true").zero?
      return false if stripped.casecmp("false").zero?

      integer_value = Integer(stripped, exception: false)
      return integer_value unless integer_value.nil?

      stripped
    end

    def fetch_users_for_report(options)
      scope = User.includes(:profile).order(:id)

      email_filter = options[:email]
      scope = scope.where("email ILIKE ?", "%#{email_filter}%") if email_filter.present?

      active_filter = options[:active]
      scope = scope.where(active: active_filter) unless active_filter.nil?

      scope
    end

    def serialize_user_report_row(user)
      profile = user.profile
      {
        id: user.id,
        email: user.email,
        active: user.active,
        name: profile&.full_name,
        last_sign_in_at: user.last_sign_in_at
      }
    end

    def serialize_setting(setting)
      {
        key: setting.key,
        value: setting.value
      }
    end
  end
end