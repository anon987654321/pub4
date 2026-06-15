# frozen_string_literal: true
# AN202: Session fixation protection — rotate session ID on login

Rails.application.config.action_dispatch.session_fixation = :delete