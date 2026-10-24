class Admin::UsersController < Admin::BaseController
  include TableCursorPagination

  before_action :set_user, only: [ :show, :confirm, :resend_confirmation, :destroy ]

  def index
    @query = params[:q].to_s.strip

    @users = User.all
    if @query.present?
      like = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      @users = @users.where("LOWER(email) LIKE ? OR LOWER(COALESCE(name, '')) LIKE ?", like, like)
    end

    @users_page = cursor_page(@users, before: params[:before], after: params[:after], timestamp_column: :created_at)
    @users = @users_page.records
    user_ids = @users.map(&:id)
    @projects_count = Project.where(user_id: user_ids).group(:user_id).count
    @api_keys_count = ApiKey.where(user_id: user_ids).group(:user_id).count
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

    if @user.projects.exists?
      purge_ids = @user.projects.find_each.map do |project|
        Logister::ProjectPurgeRequest.new(project: project, requested_by: current_user).call.id
      end
      redirect_to admin_user_path(@user),
                  notice: "Owned projects were disabled and queued for permanent deletion (purges #{purge_ids.join(', ')}). Delete the user after those purges complete."
      return
    end

    if Installation.where(claimed_by_user_id: @user.id).exists?
      redirect_to admin_user_path(@user),
                  alert: "#{@user.email} claimed this installation during first-run setup and cannot be deleted."
      return
    end

    deleted_email = @user.email
    @user.destroy!
    redirect_to admin_users_path, notice: "User #{deleted_email} was deleted."
  rescue ActiveRecord::InvalidForeignKey
    redirect_to admin_user_path(@user),
                alert: "#{@user.email} is still referenced by records they created, such as a GitHub App installation or uploaded symbol files, so the account cannot be deleted yet."
  end

  private

  def set_user
    @user = User.find_by!(uuid: params[:uuid])
  end
end
