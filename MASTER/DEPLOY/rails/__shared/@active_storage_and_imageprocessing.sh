
#!/usr/bin/env zsh

bin/rails active_storage:install
bin/rails generate migration add_avatar_to_users avatar:attachment
bin/rails db:migrate

cat <<EOF > app/models/user.rb
class User < ApplicationRecord
  has_one_attached :avatar
end
EOF

yarn add @rails/activestorage image_processing
bundle add image_processing

cat <<EOF > app/controllers/users_controller.rb
class UsersController < ApplicationController
  def update
    @user = User.find(params[:id])
    if @user.update(user_params)
      redirect_to @user, notice: "User was successfully updated."
    else
      render :edit
    end
  end

  private

  def user_params
    params.require(:user).permit(:avatar)
  end
end
EOF
