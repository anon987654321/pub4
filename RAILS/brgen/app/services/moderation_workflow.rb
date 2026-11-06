# frozen_string_literal: true

class ModerationWorkflow
  # A report for one of these on uploaded media (a tv video, a hosted track)
  # takes it out of public view at once, pending a moderator: a copyright
  # holder's notice or illegal content cannot wait for the queue. Dismissing
  # the report puts it back; resolving it leaves it held, which is the takedown.
  HOLD_REASONS = %w[copyright abuse illegal].freeze

  def self.report!(reporter:, target:, reason:, details: nil)
    new.report!(reporter: reporter, target: target, reason: reason, details: details)
  end

  def self.transition!(report:, status:, decision_reason: nil)
    new.transition!(report: report, status: status, decision_reason: decision_reason)
  end

  # One open report per reporter and target. A second press returned a second
  # row, which lengthened the queue and counted twice in the trust signals;
  # it now answers with the report already waiting.
  def report!(reporter:, target:, reason:, details: nil)
    pending = reporter && ModerationReport.find_by(user: reporter, reportable: target, status: %w[open reviewing])
    return pending if pending

    ModerationReport.transaction do
      report = ModerationReport.create!(
        user: reporter,
        reportable: target,
        reason: reason.presence || "other",
        details: details,
        status: "open"
      )
      flag_for(report, status: "open")
      hold_for_review(report)
      report
    end
  end

  def transition!(report:, status:, decision_reason: nil)
    return report unless ModerationReport::STATUSES.include?(status)

    ModerationReport.transaction do
      attrs = { status: status }
      if %w[resolved dismissed].include?(status)
        attrs[:decision_reason] = decision_reason.presence || report.reason
        attrs[:decided_at] = Time.current
      end
      report.update!(**attrs)
      case status
      when "open", "reviewing"
        flag_for(report, status: status)
      when "resolved"
        close_flags(report, status: "resolved")
        remove_content(report)
        penalize_owner(report)
      when "dismissed"
        close_flags(report, status: "dismissed")
        release_hold(report)
      end
      report
    end
  end

  private

  # report.reportable is a lazy polymorphic read, and ApplicationRecord is
  # strict_loading by default. report! creates the report with its subject in
  # memory so that path was fine; transition! takes a report a controller
  # loaded by id, which has nothing preloaded — so resolving a report raised
  # after update! had already written the new status. Admin::Reports#update
  # has been on that path the whole time.
  #
  # strict_safe does not apply: it needs reflection.klass, which a polymorphic
  # belongs_to has no single answer for.
  def subject_for(report)
    return report.reportable if report.association(:reportable).loaded?

    klass = report.reportable_type.to_s.safe_constantize
    klass.respond_to?(:strict_loading) ? klass.strict_loading(false).find_by(id: report.reportable_id) : nil
  end

  def hold_for_review(report)
    return unless HOLD_REASONS.include?(report.reason)

    subject = subject_for(report)
    return unless subject.respond_to?(:review_held_at) && subject.review_held_at.nil?

    subject.update_columns(review_held_at: Time.current, updated_at: Time.current)
  end

  # Only when no other holding report on the same item is still waiting.
  def release_hold(report)
    subject = subject_for(report)
    return unless subject.respond_to?(:review_held_at) && subject.review_held_at

    waiting = ModerationReport.where(reportable: subject, reason: HOLD_REASONS, status: %w[open reviewing])
    subject.update_columns(review_held_at: nil, updated_at: Time.current) unless waiting.exists?
  end

  def flag_for(report, status:)
    subject = subject_for(report)
    user = accountable_user(subject) || report.user
    flag = ModerationFlag.where(
      flaggable: subject,
      user: user,
      kind: report.reason
    ).where(status: %w[open reviewing]).first_or_initialize
    flag.reason = report.details.presence || report.reason
    flag.status = status
    flag.save!
  end

  def close_flags(report, status:)
    subject = subject_for(report)
    user = accountable_user(subject) || report.user
    ModerationFlag.where(flaggable: subject, user: user, kind: report.reason)
      .where(status: %w[open reviewing])
      .update_all(status: status, updated_at: Time.current)
  end

  # Resolving a report takes the content down. update_columns (not update!) so a
  # legacy record with a since-tightened validation can't block the takedown, and
  # it bumps updated_at too so the [post,…] fragment cache re-renders without it.
  def remove_content(report)
    content = subject_for(report)
    return unless content.respond_to?(:removed_at) && content.removed_at.nil?

    content.update_columns(removed_at: Time.current, updated_at: Time.current)
    # No callback ran, so the open pages are told here.
    content.try(:broadcast_removal)
  end

  def penalize_owner(report)
    subject = subject_for(report)
    user = accountable_user(subject)
    return unless user

    user.trust_signals.find_or_create_by!(
      kind: "spam_report",
      source: "moderation_report:#{report.id}"
    ) do |signal|
      signal.weight = TrustScore::SIGNAL_WEIGHTS.fetch("spam_report")
      # subject, not report.reportable: this metadata line was the one lazy
      # polymorphic read left behind by the strict_loading fix above, so
      # resolving a bare-loaded report raised HERE — after update! had
      # already written the status — the first time the new service test
      # called the real path.
      signal.metadata = { reason: report.reason, reportable: subject&.to_global_id.to_s }.to_json
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
    record.owner if record.respond_to?(:owner)
  end
end
