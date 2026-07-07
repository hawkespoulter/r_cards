class BugsController < ApplicationController
  before_action :authenticate_user!

  def index
    @bugs = Bug.all
    @bugs = @bugs.where("description ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    @bugs = @bugs.where(status: params[:status])                   if params[:status].present?
    @bugs = @bugs.order(created_at: :desc)
  end

  def create
    @bug = Bug.new(description: params[:bug][:description])
    if @bug.save
      redirect_back fallback_location: bugs_path
    else
      redirect_back fallback_location: bugs_path, alert: "Description can't be blank."
    end
  end

  def update
    @bug = Bug.find(params[:id])
    @bug.update!(status: params[:status]) if params[:status].present?
    @bug.update!(description: params[:description]) if params[:description].present?
    redirect_to bugs_path(q: params[:q], status: params[:filter_status])
  end
end
