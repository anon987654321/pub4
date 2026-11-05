# frozen_string_literal: true

# What the admin queue shows for a report's subject: a link to the reported
# page with a short excerpt of what was said, rather than "Post#12". A comment
# links to its post, at the comment. A subject without a page of its own reads
# as its excerpt; a removed one says so.
module ModerationReportsHelper
  EXCERPT_LENGTH = 120

  def report_subject(report)
    subject = report.reportable
    return t("community.subject_gone") if subject.nil?

    excerpt = report_excerpt(subject)
    path = report_subject_path(subject)
    path ? link_to(excerpt, path) : excerpt
  end

  # Reason and status in the reader's language, not the stored token humanized.
  def report_heading(report)
    "#{t("moderation_queue.reasons.#{report.reason}")} · #{t("moderation_queue.statuses.#{report.status}")}"
  end

  # One link per status filter; the one shown is marked as the current page.
  def report_filter_nav(current)
    links = Admin::ReportsController::FILTERS.map do |status|
      link_to t("moderation_queue.filters.#{status}"), admin_reports_path(status:),
              class: "chip", aria: { current: ("page" if status == current) }
    end
    tag.nav(safe_join(links, " "), class: "chips", aria: { label: t("moderation_queue.filter_label") })
  end

  def report_excerpt(subject)
    text = %i[title name content body description].lazy.map { subject.try(_1).to_s }.find(&:present?)
    text = strip_tags(text.to_s).squish
    text.present? ? truncate(text, length: EXCERPT_LENGTH) : subject.model_name.human
  end

  private

  def report_subject_path(subject)
    if subject.is_a?(Comment) && subject.association(:commentable).loaded? && subject.commentable.is_a?(Post)
      post_path(subject.commentable, anchor: dom_id(subject))
    else
      polymorphic_path(subject)
    end
  rescue NoMethodError, ActionController::UrlGenerationError => e
    # A subject with no public page of its own: the excerpt stands alone.
    Rails.logger.debug { "report subject #{subject.class.name} has no page: #{e.class}" }
    nil
  end
end
