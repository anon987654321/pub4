cd "$BASE_DIR"

# -- SET UP DEVISE FOR USER AUTHENTICATION --

bundle add devise
bundle install

bin/rails generate devise:install
bin/rails generate devise User
bin/rails db:migrate

commit_to_git "Added Devise and hooked it up to User model."

# -- SET UP OMNIAUTH FOR USER AUTHENTICATION --

bundle add omniauth-openid-connect
bundle add omniauth-google-oauth2
bundle add omniauth-snapchat

bundle install

mkdir -p app/controllers/users

cat <<EOF > app/controllers/users/omniauth_callbacks_controller.rb
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def vipps
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Vipps") if is_navigational_format?
    else
      session["devise.vipps_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\\n")
    end
  end

  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\\n")
    end
  end

  def snapchat
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Snapchat") if is_navigational_format?
    else
      session["devise.snapchat_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\\n")
    end
  end
end
EOF

mkdir -p app/models

cat <<EOF > app/models/user.rb
class User < ApplicationRecord
  devise :omniauthable, omniauth_providers: %i[vipps google_oauth2 snapchat]

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name
    end
  end
end
EOF

commit_to_git "Set up OmniAuth for Vipps, Google, and Snapchat."
