class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  rescue_from ActiveRecord::RecordNotFound, with: :redirect_to_lobby

  private

  def redirect_to_lobby
    redirect_to games_path
  end
end
