# frozen_string_literal: true

require "json"
require_relative "member"

module Council
  class Runner
    def initialize(members: default_members)
      @members = members
    end

    def review(context = {})
      findings = @members.flat_map { |member| member.review(context) }
      {
        ok: findings.none?(&:blocker?),
        findings: findings.map(&:to_h)
      }
    end

    private

    def default_members
      [
        Member.new("architect"),
        Member.new("historian"),
        Member.new("security"),
        Member.new("maintainer"),
        Member.new("operator")
      ]
    end
  end
end
