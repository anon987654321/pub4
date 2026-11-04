# frozen_string_literal: true

# One event as an iCalendar file (RFC 5545), for the event page's "add to
# calendar" link. A cancelled event keeps its UID and says STATUS:CANCELLED,
# so a calendar that imported it before marks it off instead of keeping a
# stale entry.
class EventCalendar
  def initialize(event, url:, host:)
    @event = event
    @url = url
    @host = host
  end

  def to_ics
    lines = [ "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Brgen//Events//NB", "CALSCALE:GREGORIAN",
              "METHOD:PUBLISH", *event_lines, "END:VCALENDAR" ]
    lines.map { |line| fold(line) }.join("\r\n") + "\r\n"
  end

  private

  def event_lines
    [ "BEGIN:VEVENT", "UID:event-#{@event.id}@#{@host}", "DTSTAMP:#{stamp(Time.current)}",
      "DTSTART:#{stamp(@event.starts_at)}", ("DTEND:#{stamp(@event.ends_at)}" if @event.ends_at),
      "SUMMARY:#{text(@event.title)}", optional("DESCRIPTION", @event.description),
      optional("LOCATION", location), "URL:#{@url}",
      "STATUS:#{@event.cancelled? ? 'CANCELLED' : 'CONFIRMED'}", "END:VEVENT" ].compact
  end

  def location = [ @event.location_name, @event.address ].compact_blank.uniq.join(", ")

  def optional(name, value) = value.present? ? "#{name}:#{text(value)}" : nil

  def stamp(time) = time.utc.strftime("%Y%m%dT%H%M%SZ")

  # TEXT values escape backslash, semicolon and comma, and carry newlines as \n.
  def text(value)
    value.to_s.gsub("\\") { "\\\\" }.gsub(";") { "\\;" }.gsub(",") { "\\," }.gsub(/\r?\n/) { "\\n" }
  end

  # Content lines fold at 75 octets, never inside a multibyte character.
  def fold(line)
    width = 0
    line.each_char.with_object(+"") do |char, out|
      if width + char.bytesize > 75
        out << "\r\n "
        width = 1
      end
      out << char
      width += char.bytesize
    end
  end
end
