# frozen_string_literal: true

module ReviewGate
  DEFAULT_REQUIRED_APPROVALS = 1
  DEFAULT_REQUIRED_CHECKS = [].freeze

  class Error < StandardError; end

  class Runner
    def initialize(client:, repo:, pull_number:, required_approvals: nil, required_checks: nil)
      @client = client
      @repo = repo
      @pull_number = pull_number
      @required_approvals = required_approvals || DEFAULT_REQUIRED_APPROVALS
      @required_checks = required_checks || DEFAULT_REQUIRED_CHECKS
    end

    def run
      validate_inputs!
      pull_request = fetch_pull_request
      approvals_count = approvals_for(pull_request)

      ensure_approvals!(approvals_count)
      ensure_checks!(pull_request)

      true
    end

    private

    attr_reader :client, :repo, :pull_number, :required_approvals, :required_checks

    def validate_inputs!
      raise Error, "client is required" if client.nil?
      raise Error, "repo is required" if repo.to_s.strip.empty?
      raise Error, "pull_number is required" if pull_number.nil?
    end

    def fetch_pull_request
      client.pull_request(repo, pull_number)
    end

    def approvals_for(_pull_request)
      reviews = client.pull_request_reviews(repo, pull_number)
      approved_logins = reviews
        .select { |review| review.state.to_s.casecmp("approved").zero? }
        .map { |review| review.user&.login }
        .compact
        .uniq

      approved_logins.length
    end

    def ensure_approvals!(approvals_count)
      return if approvals_count >= required_approvals

      raise Error,
            "Insufficient approvals: #{approvals_count}/#{required_approvals}"
    end

    def ensure_checks!(pull_request)
      return if required_checks.empty?

      sha = pull_request.head.sha
      statuses = client.statuses(repo, sha).map(&:context)
      missing = required_checks - statuses

      return if missing.empty?

      raise Error,
            "Missing required checks: #{missing.join(', ')}"
    end
  end

  def self.run(**kwargs)
    Runner.new(**kwargs).run
  end
end