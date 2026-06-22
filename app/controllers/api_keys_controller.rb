class ApiKeysController < ApplicationController
  include ProjectScope

  before_action :authenticate_user!
  before_action :set_project

  def create
    api_key = @project.api_keys.new(api_key_params)
    api_key.user = current_user

    if api_key.save
      respond_to do |format|
        format.turbo_stream do
          token = api_key.plain_token
          render turbo_stream: [
            turbo_stream.remove("api_keys_empty"),
            turbo_stream.prepend("api_keys_tbody", partial: "api_keys/row", locals: { api_key: api_key, project: @project }),
            turbo_stream.replace("api_key_new_token", partial: "api_keys/new_token_message", locals: { token: token }, method: :morph)
          ]
        end
        format.html do
          flash[:new_api_key_token] = api_key.plain_token
          redirect_to setup_project_path(@project, anchor: "api-keys"), notice: "API key created. Copy it now; it will not be shown again."
        end
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("api_key_new_token", partial: "api_keys/error_message", locals: { message: api_key.errors.full_messages.to_sentence }, method: :morph), status: :unprocessable_content }
        format.html { redirect_to setup_project_path(@project, anchor: "api-keys"), alert: api_key.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    api_key_identifier = params[:uuid] || params[:id]
    api_key = @project.api_keys.find_by!(uuid: api_key_identifier)
    api_key.revoke!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(api_key) }
      format.html { redirect_to setup_project_path(@project, anchor: "api-keys"), notice: "API key revoked." }
    end
  end

  private

  def set_project
    @project = current_user.manageable_projects.find_by!(uuid: project_uuid_param)
  end

  def api_key_params
    params.require(:api_key).permit(:name)
  end
end
