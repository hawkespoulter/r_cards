class SoundSettingsController < ApplicationController
  before_action :require_admin!

  def edit
    @sound_setting = SoundSetting.current
  end

  def update
    return head :not_found unless SoundSetting::KEYS.key?(params[:key])

    volume = params[:volume].to_f.clamp(0.0, 1.0)
    setting = SoundSetting.current
    setting.update!(volumes: setting.volumes.merge(params[:key] => volume))
    head :ok
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Not authorized." unless current_user.admin?
  end
end
