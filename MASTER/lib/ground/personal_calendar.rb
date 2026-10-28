# frozen_string_literal: true

require "date"
require "time"
require "fileutils"
require_relative "../io/atomic_write"
require_relative "personal_permissions"
require_relative "personal_workspace"

module Master
  module Ground
    # Read-only view of an owner-imported iCalendar file. No network access,
    # provider credentials, event mutations or recurring-event expansion.
    class PersonalCalendar
      include ::Master::Io::AtomicWrite

      READ_PERMISSION_PURPOSE = "read personal calendar events".freeze
      FILE_NAME = "calendar.ics".freeze
      MAX_IMPORT_BYTES = 2 * 1_024 * 1_024
      MAX_EVENTS = 5_000
      MAX_FIELD_CHARS = 240

      Event = Data.define(:date, :clock, :summary, :location, :all_day, :timezone, :recurring)

      def initialize(root: Master::ROOT)
        @root = File.expand_path(root)
        @permissions = PersonalPermissions.new(root: @root)
      end

      def import!(subject:, source:)
        authorize!(subject)
        source_path = File.realpath(source.to_s)
        raise ArgumentError, "calendar import must be an .ics file" unless File.extname(source_path).casecmp?(".ics")
        raise ArgumentError, "calendar import must be a regular file" unless File.file?(source_path)
        raise ArgumentError, "calendar file exceeds #{MAX_IMPORT_BYTES} bytes" if File.size(source_path) > MAX_IMPORT_BYTES

        content = File.binread(source_path).force_encoding(Encoding::UTF_8)
        raise ArgumentError, "calendar file is not valid UTF-8" unless content.valid_encoding?

        parsed = parse_calendar(content)
        workspace = PersonalWorkspace.ensure!(root: @root, subject:)
        destination = File.join(workspace, FILE_NAME)
        raise PersonalWorkspace::PermissionDenied, "calendar path must not be a symlink" if File.symlink?(destination)
        authorize!(subject)
        write_atomic(destination, content, mode: 0o600)

        { filename: File.basename(source_path), event_count: parsed.fetch(:events).size,
          recurring_series: parsed.fetch(:recurring_series) }
      rescue Errno::ENOENT
        raise ArgumentError, "calendar source does not exist"
      end

      def status(subject:)
        authorize!(subject)
        path = calendar_path(subject)
        return { imported: false, path:, event_count: 0, recurring_series: 0 } unless File.file?(path) && !File.symlink?(path)

        parsed = parse_calendar(read_calendar(path))
        { imported: true, path:, event_count: parsed.fetch(:events).size,
          recurring_series: parsed.fetch(:recurring_series) }
      end

      def events_for(subject:, date: Date.today)
        authorize!(subject)
        date = Date.iso8601(date.to_s) unless date.is_a?(Date)
        path = calendar_path(subject)
        raise ArgumentError, "no calendar imported; use /agenda import /path/to/calendar.ics" unless File.file?(path)
        raise PersonalWorkspace::PermissionDenied, "calendar path must not be a symlink" if File.symlink?(path)

        parsed = parse_calendar(read_calendar(path))
        { date:, events: parsed.fetch(:events).select { |event| event.date == date }
            .sort_by { |event| [event.clock.to_s, event.summary] },
          recurring_series: parsed.fetch(:recurring_series), total_events: parsed.fetch(:events).size }
      end

      private

      def authorize!(subject)
        id = subject.to_s.strip
        raise PersonalWorkspace::PermissionDenied, "pair this session before using a personal calendar" if id.empty?
        allowed = @permissions.allowed?(
          scope: "calendar_read", subject: id, purpose: READ_PERMISSION_PURPOSE,
        )
        raise PersonalWorkspace::PermissionDenied, "calendar access is disabled; use /privacy grant calendar_read in the paired local session" unless allowed
      end

      def calendar_path(subject)
        PersonalWorkspace.dir_for(subject, root: @root).then { |dir| File.join(dir, FILE_NAME) }
      end

      def read_calendar(path)
        raise ArgumentError, "calendar file exceeds #{MAX_IMPORT_BYTES} bytes" if File.size(path) > MAX_IMPORT_BYTES
        content = File.binread(path).force_encoding(Encoding::UTF_8)
        raise ArgumentError, "calendar file is not valid UTF-8" unless content.valid_encoding?

        content
      end

      def parse_calendar(content)
        lines = unfold(content.sub(/\A\uFEFF/, ""))
        raise ArgumentError, "not an iCalendar file" unless lines.include?("BEGIN:VCALENDAR") && lines.include?("END:VCALENDAR")

        events = []
        current = nil
        lines.each do |line|
          case line
          when "BEGIN:VEVENT"
            raise ArgumentError, "nested calendar event" if current
            current = {}
          when "END:VEVENT"
            raise ArgumentError, "calendar event ended without a start" unless current
            events << parse_event(current)
            raise ArgumentError, "calendar has more than #{MAX_EVENTS} events" if events.size > MAX_EVENTS
            current = nil
          else
            next unless current
            key, value = line.split(":", 2)
            next unless key && value
            name, *params = key.split(";")
            current[name.upcase] = { value:, params: }
          end
        end
        raise ArgumentError, "calendar event was not closed" if current

        { events: events.freeze, recurring_series: events.count(&:recurring) }
      end

      def unfold(content)
        rows = []
        content.gsub("\r\n", "\n").gsub("\r", "\n").each_line do |line|
          value = line.chomp
          if value.start_with?(" ", "\t") && !rows.empty?
            rows[-1] << value[1..]
          else
            rows << value
          end
        end
        rows
      end

      def parse_event(properties)
        start = properties["DTSTART"]
        raise ArgumentError, "calendar event is missing DTSTART" unless start

        raw = start.fetch(:value)
        params = start.fetch(:params)
        all_day = raw.match?(/\A\d{8}\z/)
        if all_day
          date = Date.strptime(raw, "%Y%m%d")
          clock = nil
          timezone = nil
        elsif raw.match?(/\A\d{8}T\d{6}Z\z/)
          utc = Time.strptime(raw, "%Y%m%dT%H%M%SZ").utc
          local = utc.getlocal
          date = local.to_date
          clock = local.strftime("%H:%M")
          timezone = local.zone
        elsif raw.match?(/\A\d{8}T\d{6}\z/)
          date = Date.strptime(raw[0, 8], "%Y%m%d")
          clock = "#{raw[9, 2]}:#{raw[11, 2]}"
          timezone = params.find { |item| item.start_with?("TZID=") }&.delete_prefix("TZID=")
        else
          raise ArgumentError, "unsupported DTSTART format"
        end

        summary = safe_field(properties.dig("SUMMARY", :value) || "Untitled event")
        location = safe_field(properties.dig("LOCATION", :value).to_s)
        recurring = properties.key?("RRULE") || properties.key?("RDATE")
        Event.new(date:, clock:, summary:, location:, all_day:, timezone:, recurring:)
      rescue Date::Error, ArgumentError => e
        raise ArgumentError, "invalid calendar event: #{e.message}"
      end

      def safe_field(value)
        value.to_s.gsub(/\\[nN]/, " ").gsub("\\,", ",").gsub("\\;", ";").gsub("\\\\", "\\")
          .gsub(/[[:cntrl:]]/, " ").gsub(/\s+/, " ").strip[0, MAX_FIELD_CHARS]
      end
    end
  end
end
