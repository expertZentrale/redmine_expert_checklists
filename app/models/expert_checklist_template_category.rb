# Groups checklist templates in the editor's "Add from template" menu. Global,
# managed by admins; ordered by position (drag handles on the settings page).
class ExpertChecklistTemplateCategory < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  include Redmine::SafeAttributes

  has_many :templates, :class_name => 'ExpertChecklistTemplate', :foreign_key => 'category_id',
                       :dependent => :nullify, :inverse_of => :category

  acts_as_positioned

  validates :name, :presence => true, :length => { :maximum => 255 }

  scope :sorted, lambda { order(:position, :name) }

  safe_attributes 'name', 'position'

  def to_s
    name.to_s
  end
end
