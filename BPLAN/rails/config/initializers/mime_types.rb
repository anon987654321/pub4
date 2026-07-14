# frozen_string_literal: true

Mime::Type.register "text/calendar", :ics unless Mime::Type.lookup_by_extension(:ics)