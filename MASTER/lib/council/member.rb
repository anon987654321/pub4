# frozen_string_literal: true

module Council
  Finding = Struct.new(:member, :severity, :message, :path, keyword_init: true) do
    def blocker? = severity.to_s == "blocker"
    def to_h = { member: member, severity: severity, message: message, path: path }.compact
  end

  class Member
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def review(_context)
      []
    end

    private

    def finding(severity, message, path: nil)
      Finding.new(member: name, severity: severity, message: message, path: path)
    end
  end
end
