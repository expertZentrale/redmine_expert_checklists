# A reusable list of checklist items. Global (no project; admins manage them)
# or of a project (users with "Manage checklist templates"); public, or private
# to its author. The issue form offers the templates of the issue's project and
# the global ones, for its tracker or for all trackers.
#
# A template can be the default: new issues created through the issue form or
# the REST API start with it. Project templates win over global ones, tracker
# templates over those for all trackers. Mail-created and copied issues get no
# default.
class ExpertChecklistTemplate < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  include Redmine::SafeAttributes

  belongs_to :project, :optional => true
  belongs_to :tracker, :optional => true
  belongs_to :author, :class_name => 'User', :optional => true
  belongs_to :category, :class_name => 'ExpertChecklistTemplateCategory', :inverse_of => :templates,
                        :optional => true

  validates :name, :presence => true, :length => { :maximum => 255 }
  validate :validate_items

  before_validation :normalize_items

  scope :sorted, lambda { order(:name, :id) }
  scope :global, lambda { where(:project_id => nil) }

  # Public ones and the user's own private ones - also for admins: somebody
  # else's private template is never offered or applied.
  scope :usable_by, lambda { |user|
    user.logged? ? where('is_public = ? OR author_id = ?', true, user.id) : where(:is_public => true)
  }

  # What the issue form offers for an issue of this project and tracker.
  scope :available_for, lambda { |project, tracker, user = User.current|
    where(:project_id => [nil, project.id]).where(:tracker_id => [nil, tracker && tracker.id]).usable_by(user)
  }

  safe_attributes 'name', 'items', 'category_id', 'tracker_id', 'is_public', 'is_default'

  # The template a new issue of this project and tracker starts with, or nil.
  def self.default_for(project, tracker, user = User.current)
    return nil unless project && RedmineExpertChecklists.enabled?(project)

    available_for(project, tracker, user).where(:is_default => true).to_a.min_by do |template|
      [template.project_id ? 0 : 1, template.tracker_id ? 0 : 1, template.id]
    end
  end

  # Template text to item rows: one per line, "-- " starts a section, "[x] " a
  # done item; list bullets, "[ ] " and blank lines are dropped. The editor's
  # script reads pasted text the same way (parseLines).
  def self.parse(text)
    text.to_s.split(/\r?\n/).map do |line|
      subject = line.strip
      section = subject.start_with?('--')
      subject = subject.sub(/\A--\s*/, '').strip if section
      done = !section && subject.match?(/\A\[[xX]\]/)
      subject = subject.sub(/\A(?:[-*•]\s+|\[[ xX]?\]\s*)/, '').strip
      next if subject.empty?

      RedmineExpertChecklists.snapshot(subject[0, RedmineExpertChecklists::SUBJECT_MAX], done, section)
    end.compact
  end

  def rows
    self.class.parse(items)
  end

  # Unsaved items of ours, positioned 1..n.
  def build_items
    rows.each_with_index.map do |row, index|
      ExpertChecklistItem.new(:subject => row['subject'], :is_done => row['is_done'],
                              :is_section => row['is_section'], :position => index + 1)
    end
  end

  # Whether items still are this template's list (subjects and sections, in
  # order): a default the user has not touched may be swapped for another one.
  def matches?(items)
    rows.map { |row| [row['subject'], row['is_section']] } ==
      items.map { |item| [item.subject.to_s.strip, item.is_section?] }
  end

  def global?
    project_id.nil?
  end

  # Global ones: admins. Project ones: "Manage checklist templates" there;
  # somebody else's private template only for admins.
  def editable_by?(user = User.current)
    return user.admin? if global?
    return false unless user.allowed_to?(:manage_expert_checklist_templates, project)

    is_public? || author_id == user.id || user.admin?
  end

  def to_s
    name.to_s
  end

  private

  def normalize_items
    self.items = items.to_s.gsub(/\r\n?/, "\n").strip
  end

  def validate_items
    errors.add(:items, :blank) if rows.empty?
  end
end
