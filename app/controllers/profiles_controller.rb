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

  # Fired from the navbar's card-back picker via fetch() — the swap already
  # happens instantly client-side, so this just persists the choice to the
  # user's profile in the background. No body needed on success.
  def update_card_back
    if User::CARD_BACKS.key?(params[:card_back])
      current_user.update(card_back: params[:card_back])
      head :ok
    else
      head :unprocessable_entity
    end
  end

  # Fired from the navbar's high-vis toggle. Unlike the card-back picker,
  # this can't be applied instantly client-side (it'd mean re-deriving every
  # card image on the page, not just the face-down ones), so the JS reloads
  # the page after this persists — server-rendered fronts pick up the new
  # deck on that next render via ApplicationHelper#card_asset.
  def update_high_vis_fronts
    current_user.update(high_vis_fronts: ActiveModel::Type::Boolean.new.cast(params[:high_vis_fronts]))
    head :ok
  end
end
