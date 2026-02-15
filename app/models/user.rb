class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable

  has_many :projects, dependent: :destroy
  has_many :api_keys, dependent: :destroy

  before_validation :ensure_uuid

  validates :uuid, presence: true, uniqueness: true

  def to_param
    uuid
  end

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
