module ExpertChecklistsHelper
  # Subjects are plain text with Redmine links (#123, r456, document:...), not
  # wiki markup: a formatter would drop text such as "<div>" (CommonMark
  # sanitizes it away) and could turn "1. step" into a list.
  def expert_checklist_subject(item, issue = nil)
    textilizable(item.subject.to_s, :object => issue, :formatting => false, :only_path => true)
  end

  def expert_checklist_progress(items)
    checkable = items.reject(&:is_section?)
    [checkable.count(&:is_done?), checkable.size]
  end

  # Redmine 6+ draws icons from an SVG sprite; on 5.x the label stands alone and
  # the icon comes from the "icon icon-*" class of the element.
  def expert_checklist_icon(name, label = nil)
    if respond_to?(:sprite_icon)
      sprite_icon(name, label)
    else
      label.to_s
    end
  end

  # Items the form editor starts with: the in-memory association (it carries
  # the user's unsaved rows when the form is re-rendered after a refresh or a
  # validation error), or the source issue's items on a copy form.
  def expert_checklist_form_items(issue)
    items = issue.expert_checklist_items.reject(&:marked_for_destruction?)
    if items.empty? && issue.new_record? && issue.expert_checklist_form.nil?
      source = issue.expert_checklists_copy_source
      if source && source.id
        items = source.expert_checklist_items.map do |item|
          ExpertChecklistItem.new(:subject => item.subject, :is_done => item.is_done,
                                  :is_section => item.is_section, :position => item.position)
        end
      end
    end
    items.sort_by.with_index { |item, index| [item.position.to_i, index] }
  end

  def expert_checklist_config
    {
      :labels => {
        :item => l(:label_expert_checklist_item),
        :section => l(:label_expert_checklist_section),
        :remove => l(:button_delete),
        :moveUp => l(:label_expert_checklist_move_up),
        :moveDown => l(:label_expert_checklist_move_down),
        :moved => l(:text_expert_checklist_moved),
        :saveFailed => l(:error_expert_checklist_save_failed),
        :hideDone => l(:label_expert_checklist_hide_done),
        :showDone => l(:label_expert_checklist_show_done)
      }
    }
  end
end
