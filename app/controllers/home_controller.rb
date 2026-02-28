class HomeController < ApplicationController
  def show
    redirect_to dashboard_path if user_signed_in?
  end

  def about
  end

  def privacy
  end

  def terms
  end
end
