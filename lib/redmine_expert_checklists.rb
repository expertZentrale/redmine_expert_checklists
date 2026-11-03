# Shared helpers of the checklist plugin: settings readers, permission checks
# and the snapshot format that history entries are built from.
#
# Everything is gated by the project module :expert_checklists. While it is off
# in a project the plugin renders nothing there, refuses its API and ignores
# nested attributes, so it can be installed next to RedmineUP Checklists and
# switched on project by project (the legacy import enables it at cutover).
module RedmineExpertChecklists
  PLUGIN_ID = :redmine_expert_checklists
  MODULE = :expert_checklists
  # JournalDetail#property of our history entries: one detail per changed item,
  # prop_key = item id, old_value/value = snapshot JSON (nil = added/removed).
  DETAIL_PROPERTY = 'expert_checklist'.freeze
  SUBJECT_MAX = 1000
  NOTIFICATION_MODES = %w(issue_updated always never).freeze

  module_function

  def settings
    Setting.respond_to?(:plugin_redmine_expert_checklists) ? (Setting.plugin_redmine_expert_checklists || {}) : {}
  end

  def setting_on?(name)
    settings[name.to_s].to_s == '1'
  end

  # issue_updated (default): mail checklist changes when Redmine mails issue
  # updates at all. always / never: regardless of that event.
  def notification_mode
    mode = settings['notifications'].to_s
    NOTIFICATION_MODES.include?(mode) ? mode : 'issue_updated'
  end

  def notify_enabled?
    case notification_mode
    when 'never' then false
    when 'always' then true
    else Setting.notified_events.include?('issue_updated')
    end
  end

  # True when RedmineUP Checklists is installed next to us. A file test rather
  # than Redmine::Plugin.installed?, because routes.rb asks before every plugin
  # is registered; it is also what RedmineUP Agile itself checks.
  def redmineup_present?
    File.exist?(File.join(Redmine::Plugin.directory.to_s, 'redmine_checklists', 'init.rb'))
  end

  def enabled?(project)
    !!(project && project.module_enabled?(MODULE))
  end

  def viewable?(issue, user = User.current)
    issue && enabled?(issue.project) && user.allowed_to?(:view_expert_checklists, issue.project)
  end

  # May tick and untick items on the issue page.
  def tickable?(issue, user = User.current)
    issue && enabled?(issue.project) &&
      (user.allowed_to?(:done_expert_checklists, issue.project) ||
       user.allowed_to?(:edit_expert_checklists, issue.project))
  end

  # May add, rename, reorder and delete items (issue form, REST API).
  def editable?(issue, user = User.current)
    issue && enabled?(issue.project) && user.allowed_to?(:edit_expert_checklists, issue.project)
  end

  # Done ratio follows the checklist only when the done ratio is an issue field
  # (not taken from the status) and not derived from subtasks.
  def done_ratio_applies?(issue)
    setting_on?(:done_ratio_from_checklist) && Issue.use_field_for_done_ratio? &&
      !issue.done_ratio_derived?
  end

  # Floors to tens like RedmineUP did (2 of 3 done = 60 %). nil without any
  # non-section item, so an empty checklist never resets the field.
  def done_ratio_for(items)
    checkable = items.reject { |item| item_section?(item) }
    return nil if checkable.empty?

    done = checkable.count { |item| item_done?(item) }
    (done * 10 / checkable.size) * 10
  end

  def item_section?(item)
    item.is_a?(Hash) ? item['is_section'] : item.is_section?
  end

  def item_done?(item)
    item.is_a?(Hash) ? item['is_done'] : item.is_done?
  end

  # The history snapshot of one item. Keys and order match RedmineUP's custom
  # field checklist JSON, so both formats share one parser.
  def snapshot(subject, is_done, is_section)
    { 'subject' => subject.to_s, 'is_done' => !!is_done, 'is_section' => !!is_section }
  end

  # Item id => snapshot, read straight from the database.
  def snapshots_for(issue_id)
    ExpertChecklistItem.where(:issue_id => issue_id).pluck(:id, :subject, :is_done, :is_section).
      each_with_object({}) do |(id, subject, is_done, is_section), map|
        map[id] = snapshot(subject, is_done, is_section)
      end
  end

  # Canonical JSON (fixed key order, no whitespace): equal snapshots compare
  # equal as strings, which the merge relies on.
  def dump(snapshot)
    snapshot && snapshot.to_json
  end
end
