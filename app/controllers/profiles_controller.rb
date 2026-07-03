class ProfilesController < ApplicationController
  # Lightweight display-name change that skips Devise's current-password
  # requirement (update_with_password on Users::RegistrationsController#update)
  # — that check exists to protect email/password changes, not a plain rename.
  def update_name
    if current_user.update(name: params[:user][:name])
      redirect_to edit_user_registration_path, notice: "Display name updated!"
    else
      redirect_to edit_user_registration_path, alert: current_user.errors.full_messages.to_sentence
    end
  end
end
