class OmniauthCallbacksController < ApplicationController
  def facebook
    user = current_user || User.find_by_email(auth_hash.info.email)

    unless user
      user = User.anonymous!
      user.email = auth_hash.info.email
      user.name = auth_hash.info.name
      user.image = auth_hash.info.image
    end

    user.build_or_update_authentication(auth_hash)
    user.save!

    sign_in user, event: :authentication

    redirect_to root_url
  end

  def google_oauth2
    user = current_user || User.find_by_email(auth_hash.info.email)

    unless user
      user = User.anonymous!
      user.email = auth_hash.info.email
      user.name = auth_hash.info.name
      user.avatar = open(auth_hash.info.image) if auth_hash.info.image
    end

    user.build_or_update_authentication(auth_hash)
    user.save!

    sign_in user, event: :authentication

    redirect_to root_url
  end

protected
  def auth_hash
    request.env["omniauth.auth"]
  end
end

