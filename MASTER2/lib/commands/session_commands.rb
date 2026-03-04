# frozen_string_literal: true

module Commands
  module SessionCommands
    OUTPUT_JOINER = "\",\n            \""
    PUTS_LINE_PREFIX = "\"\n              puts \""

    def manage_session(session_identifier:, current_user:, tags: nil)
      session_record = fetch_session(session_identifier, current_user)
      return result(:not_found, ["Session not found"]) unless session_record

      tag_list = Array(tags)
      action = decide_session_action(session_record, tag_list)

      perform_session_action(action, session_record, current_user, tag_list)
    end

    private

    def fetch_session(session_identifier, current_user)
      Session
        .includes(:user, :events)
        .find_by(id: session_identifier, user_id: current_user.id)
    end

    def decide_session_action(session_record, tag_list)
      return :resume if session_record.active?
      return :start if tag_list.any?

      :show
    end

    def perform_session_action(action, session_record, current_user, tag_list)
      case action
      when :start
        start_session(session_record, current_user, tag_list)
      when :resume
        resume_session(session_record, current_user)
      when :show
        show_session(session_record)
      else
        result(:invalid_action, ["Invalid session action: #{action}"])
      end
    end

    def start_session(session_record, current_user, tag_list)
      session_record.update!(
        started_at: current_timestamp,
        status: "active",
        tag_list: tag_list
      )

      result(:started, ["Session started", session_payload(session_record, current_user)])
    end

    def resume_session(session_record, current_user)
      session_record.update!(resumed_at: current_timestamp)

      result(:resumed, ["Session resumed", session_payload(session_record, current_user)])
    end

    def show_session(session_record)
      result(:shown, [session_payload(session_record, session_record.user)])
    end

    def current_timestamp
      Time.current.utc.iso8601
    end

    def session_payload(session_record, user_record)
      {
        id: session_record.id,
        user_id: user_record.id,
        status: session_record.status,
        started_at: session_record.started_at&.utc&.iso8601,
        resumed_at: session_record.resumed_at&.utc&.iso8601,
        events_count: session_record.events.size
      }
    end

    def result(status, messages)
      { status: status, messages: messages }
    end
  end
end