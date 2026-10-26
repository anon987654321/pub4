# frozen_string_literal: true

require "time"

module Master
  module Ground
    # "tomorrow at 9", "in 20 minutes", "i morgen kl 9" or an ISO-8601 time, read in
    # the owner's timezone and answered in UTC. A model asked to write the ISO time
    # itself guessed the zone; this reads the clock the person meant.
    module ReminderTime
      UNITS = { "minute" => 60, "min" => 60, "minutt" => 60, "hour" => 3600, "time" => 3600,
                "day" => 86_400, "dag" => 86_400 }.freeze
      RELATIVE = /\A(?:in|om)\s+(\d+)\s+(minutes?|mins?|minutt(?:er)?|hours?|timer?|days?|dag(?:er)?)\z/i
      CLOCK = /\A(?:(today|tomorrow|i\s+dag|i\s+morgen)\s+)?(?:at\s+|kl\.?\s+)?(\d{1,2})(?::|\.)?(\d{2})?\s*(am|pm)?
              (?:\s+(today|tomorrow|i\s+dag|i\s+morgen))?\z/ix
      ZONE_LOCK = Mutex.new

      module_function

      # nil when the text is none of the accepted shapes.
      def resolve(text, zone: nil, now: Time.now)
        value = text.to_s.strip.downcase
        return Time.iso8601(text.to_s.strip).utc if value.match?(/\A\d{4}-\d{2}-\d{2}t/)

        relative(value, now) || clock(value, zone, now)
      rescue ArgumentError
        nil
      end

      def relative(value, now)
        match = value.match(RELATIVE) or return
        seconds = UNITS.find { |unit, _| match[2].start_with?(unit) }&.last
        seconds && (now + (Integer(match[1]) * seconds)).utc
      end

      def clock(value, zone, now)
        match = value.match(CLOCK) or return
        hour = hour_of(Integer(match[2]), match[4])
        minute = Integer(match[3] || 0)
        return unless hour.between?(0, 23) && minute.between?(0, 59)

        in_zone(zone) { at(now.getlocal, hour, minute, match[1] || match[5]) }
      end

      def hour_of(hour, meridian)
        return hour unless meridian
        return hour % 12 if meridian == "am"

        (hour % 12) + 12
      end

      # A named day is that day; a bare time is the next time the clock reads it.
      def at(local, hour, minute, day)
        tomorrow = day.to_s.match?(/tomorrow|morgen/)
        date = tomorrow ? local.to_date + 1 : local.to_date
        target = Time.local(date.year, date.month, date.day, hour, minute)
        target += 86_400 if day.nil? && target <= local
        target.utc
      end

      # Time.local reads TZ, which is process-wide, so the swap is held under a lock.
      def in_zone(zone)
        return yield if zone.to_s.empty?

        ZONE_LOCK.synchronize do
          previous = ENV.fetch("TZ", nil)
          ENV["TZ"] = zone
          begin
            yield
          ensure
            previous ? ENV["TZ"] = previous : ENV.delete("TZ")
          end
        end
      end
    end
  end
end
