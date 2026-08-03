# frozen_string_literal: true

class ModerationWorkflow
  def self.report!(reporter:, target:, reason:, details: nil)
    new.report!(reporter: reporter, target: target, reason: reason, details: details)
  end

  def self.transition!(report:, status:)
    new.transition!(report: report, status: status)
  end

  def report!(reporter:, target:, reason:, details: nil)
    report = ModerationReport.create!(
      user: reporter,
      reportable: target,
      reason: reason.presence || "other",
      details: details,
      status: "open"
    )
    flag_for(report, status: "open")
    report
  end

  def transition!(report:, status:)
    return report unless ModerationReport::STATUSES.include?(status)

    report.update!(status: status)
    case status
    when "open", "reviewing"
      flag_for(report, status: status)
    when "resolved"
      close_flags(report, status: "resolved")
      remove_content(report)
      penalize_owner(report)
    when "dismissed"
      close_flags(report, status: "dismissed")
    end
    report
  end

  private

  def flag_for(report, status:)
    user = accountable_user(report.reportable) || report.user
    flag = ModerationFlag.where(
      flaggable: report.reportable,
      user: user,
      kind: report.reason
    ).where(status: %w[open reviewing]).first_or_initialize
    flag.reason = report.details.presence || report.reason
    flag.status = status
    flag.save!
  end

  def close_flags(report, status:)
    user = accountable_user(report.reportable) || report.user
    ModerationFlag.where(flaggable: report.reportable, user: user, kind: report.reason)
      .where(status: %w[open reviewing])
      .update_all(status: status, updated_at: Time.current)
  end

  # Resolving a report takes the content down. update_columns (not update!) so a
  # legacy record with a since-tightened validation can't block the takedown, and
  # it bumps updated_at too so the [post,…] fragment cache re-renders without it.
  def remove_content(report)
    content = report.reportable
    return unless content.respond_to?(:removed_at) && content.removed_at.nil?

    content.update_columns(removed_at: Time.current, updated_at: Time.current)
  end

  def penalize_owner(report)
    user = accountable_user(report.reportable)
    return unless user

    user.trust_signals.find_or_create_by!(
      kind: "spam_report",
      source: "moderation_report:#{report.id}"
    ) do |signal|
      signal.weight = TrustScore::SIGNAL_WEIGHTS.fetch("spam_report")
      signal.metadata = { reason: report.reason, reportable: report.reportable.to_global_id.to_s }.to_json
    end
    TrustScore.new(user: user).call
  end

  def accountable_user(record)
    return record if record.is_a?(User)

    # The reported record arrives from a signed GlobalID with nothing
    # preloaded, and ApplicationRecord sets strict_loading_by_default. Asking
    # for its author would raise wherever violations are not downgraded to a
    # log line -- which is every environment except development.
    record.strict_loading!(false)
    return record.user if record.respond_to?(:user)
    return record.seller if record.respond_to?(:seller)
    return record.owner if record.respond_to?(:owner)
  end
end
