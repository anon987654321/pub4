class UsersController < Forem::ApplicationController
  skip_before_action :load_categories, :build_topic, :build_reply, :set_visit, only: [:avatar]

  def show
  end

  def avatar
    user = User.find(params[:id])
    image = Quilt::Identicon.new user.email.strip.downcase, scale: 5, transparent: true
    # image = Quilt::Identicon.new user.email.strip.downcase, scale: 5, transparent: true, format: "svg"

    send_data image.to_blob, type: "image/png", disposition: "inline"
    # send_data image.to_blob, type: "image/svg+xml", disposition: "inline"
  end

protected
  def user_params
    params.require(:user).permit(:email, :name, :username, :image, :country, :gender, :password, :password_confirmation, :remember_me, :persistence_token, :provider, :uid, :anon_id)
  end
end

