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
    api_key_identifier = params[:uuid] || params[:id]
    api_key = @project.api_keys.find_by!(uuid: api_key_identifier)
    api_key.revoke!

    redirect_to project_path(@project), notice: "API key revoked."
  end

  private

  def set_project
    project_identifier = params[:project_uuid] || params[:project_id]
    @project = current_user.projects.find_by!(uuid: project_identifier)
  end

  def api_key_params
    params.require(:api_key).permit(:name)
  end
end
