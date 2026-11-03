# One checklist item (or section heading) of an issue.
#
# Items are written two ways: through the issue form as nested attributes (core
# journalizes those together with the rest of the edit, see IssuePatch), and
# directly - a tick on the issue page or the REST API - through
# RedmineExpertChecklists::Recorder, which bundles quick successive changes into
# one journal and one delayed mail.
class ExpertChecklistItem < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  include Redmine::SafeAttributes

  belongs_to :issue, :inverse_of => :expert_checklist_items

  validates :issue, :presence => true
  validates :subject, :presence => true,
                      :length => { :maximum => RedmineExpertChecklists::SUBJECT_MAX }

  before_validation :strip_subject
  before_create :append_position

  scope :ordered, lambda { order(:position, :id) }
  scope :checkable, lambda { where(:is_section => false) }

  safe_attributes 'subject', 'is_done', 'is_section', 'position'

  # Remembers whether a caller chose the position (the issue form always does).
  def position=(value)
    @position_given = value.present?
    super
  end

  def snapshot
    RedmineExpertChecklists.snapshot(subject, is_done, is_section)
  end

  # "[+] done", "[-] open", sections as plain lines: RedmineUP's export format,
  # kept so CSV consumers and saved exports read the same.
  def to_export_line
    return subject.to_s if is_section?

    "#{is_done? ? '[+]' : '[-]'} #{subject}"
  end

  private

  # Subjects are single-line; pasted line breaks would break the export format.
  def strip_subject
    self.subject = subject.to_s.gsub(/[\r\n]+/, ' ').strip unless subject.nil?
  end

  # Items created without a position (REST API) go to the end of the list.
  def append_position
    return if @position_given && position.to_i > 0

    last = issue_id ? self.class.where(:issue_id => issue_id).maximum(:position).to_i : 0
    self.position = last + 1
  end
end
