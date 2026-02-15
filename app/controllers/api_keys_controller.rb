class ApiKeysController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project

  def create
    api_key = @project.api_keys.new(api_key_params)
    api_key.user = current_user

    if api_key.save
      flash[:new_api_key_token] = api_key.plain_token
      redirect_to project_path(@project), notice: "API key created. Copy it now; it will not be shown again."
    else
      redirect_to project_path(@project), alert: api_key.errors.full_messages.to_sentence
    end
  end

  def destroy
    api_key = @project.api_keys.find(params[:id])
    api_key.revoke!

    redirect_to project_path(@project), notice: "API key revoked."
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end

  def api_key_params
    params.require(:api_key).permit(:name)
  end
end
