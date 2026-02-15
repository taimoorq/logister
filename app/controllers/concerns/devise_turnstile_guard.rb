module DeviseTurnstileGuard
  private

  def turnstile_failed_redirect(path)
    flash[:alert] = "Please complete the verification challenge and try again."
    redirect_to path
  end
end
