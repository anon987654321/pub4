# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/copy-review
    #
    # Reviews supplied creative against a caller-supplied product snapshot.
    # The snapshot is not independently authenticated, so the response labels
    # its provenance honestly. One review costs one check from the same monthly
    # quota as source lint. The receipt stores hashes and finding codes only.
    class CopyReviewsController < BaseController
      rate_limit to: 60, within: 1.minute, by: -> { @api_key.id },
                 with: -> { refuse(:too_many_requests, "rate_limited") }

      def create
        if request.content_length.to_i > CopyReviewCheck::MAX_INPUT_BYTES + 4_096
          return refuse(:payload_too_large, "payload_too_large")
        end

        prepared = CopyReviewCheck.prepare(
          creative: params[:creative],
          product: params[:product],
          market: params[:market]
        )
        return refuse(:payment_required, "subscription_inactive") unless @api_key.entitling?

        outcome = ApiKey.transaction do
          usage = @api_key.charge!(1)
          next unless usage

          checked = CopyReviewCheck.call(prepared)
          report = checked.report
          request_id = SecureRandom.uuid
          receipt = ApiCopyReview.create!(
            api_key: @api_key,
            request_id:,
            status: report.status.to_s,
            report_version: report.version,
            creative_sha256: checked.creative_sha256,
            product_sha256: checked.product_sha256,
            reviewer_sha256: checked.reviewer_sha256,
            source_trust: "caller_supplied_unverified",
            summary: report.summary,
            finding_codes: report.findings.map { |finding| finding.code.to_s }
          )
          [usage, checked, receipt]
        end

        return refuse(:too_many_requests, "quota_exhausted", usage: @api_key.usage.to_h) unless outcome

        usage, checked, receipt = outcome
        render json: {
          request_id: receipt.request_id,
          review: checked.report.to_h,
          provenance: {
            creative_sha256: receipt.creative_sha256,
            product_sha256: receipt.product_sha256,
            reviewer_sha256: receipt.reviewer_sha256,
            source_trust: receipt.source_trust,
            stored_copy: false,
            certification: false
          },
          usage: usage.to_h
        }
      rescue CopyReviewCheck::InvalidInput => e
        refuse(:unprocessable_entity, "invalid_request", detail: e.message)
      end
    end
  end
end
