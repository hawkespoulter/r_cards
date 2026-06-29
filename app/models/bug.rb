class Bug < ApplicationRecord
  enum status: { open: 0, resolved: 1 }
  validates :description, presence: true
end
