class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :confirm, :resend_confirmation, :destroy ]

  def index
    @query = params[:q].to_s.strip

    @users = User.all
    if @query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      @users = @users.where("LOWER(email) LIKE ? OR LOWER(COALESCE(name, '')) LIKE ?", like, like)
    end

    @users = @users
      .left_joins(:projects, :api_keys)
      .select("users.*, COUNT(DISTINCT projects.id) AS projects_count, COUNT(DISTINCT api_keys.id) AS api_keys_count")
      .group("users.id")
      .order(created_at: :desc)
  end

  def show
    @owned_projects = @user.projects.order(created_at: :desc)
    @api_keys = @user.api_keys.includes(:project).order(created_at: :desc).limit(20)
    @shared_projects = @user.shared_projects.order(created_at: :desc)
  end

  def confirm
    if @user.confirmed?
      redirect_to admin_user_path(@user), notice: "User is already confirmed."
      return
    end

    @user.confirm
    redirect_to admin_user_path(@user), notice: "User confirmed."
  end

  def resend_confirmation
    if @user.confirmed?
      redirect_to admin_user_path(@user), notice: "User is already confirmed."
      return
    end

    @user.send_confirmation_instructions
    redirect_to admin_user_path(@user), notice: "Confirmation instructions sent."
  end

  def destroy
    if @user == current_user
      redirect_to admin_user_path(@user), alert: "You cannot delete your own account from admin."
      return
    end

    deleted_email = @user.email
    @user.destroy!
    redirect_to admin_users_path, notice: "User #{deleted_email} was deleted."
  end

  private

  def set_user
    @user = User.find_by!(uuid: params[:uuid])
  end
end
