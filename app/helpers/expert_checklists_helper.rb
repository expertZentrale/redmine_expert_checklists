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
  # validation error), the source issue's items on a copy form, or on a new
  # issue the default template. The default fills an editor that is empty and
  # was not filled by a default before, also on a refresh (the tracker or
  # project changed); a default the user has not touched follows such a
  # change, one the user edited or emptied stays. Sets
  # @expert_checklist_default_template, the default the rows came from, which
  # the form carries along.
  def expert_checklist_form_items(issue)
    @expert_checklist_default_template = nil
    items = issue.expert_checklist_items.reject(&:marked_for_destruction?)
    if issue.new_record?
      applied = issue.expert_checklist_template_id.presence &&
                ExpertChecklistTemplate.find_by(:id => issue.expert_checklist_template_id)
      if applied && !applied.matches?(items)
        @expert_checklist_default_template = applied
      elsif applied || items.empty?
        source = issue.expert_checklists_copy_source
        if source && source.id
          items = RedmineExpertChecklists.copy_source_items(source)
        else
          default = ExpertChecklistTemplate.default_for(issue.project, issue.tracker)
          @expert_checklist_default_template = default
          # Same default again: keep the rows, ticks included.
          items = default ? default.build_items : [] unless applied && default == applied
        end
      end
    end
    items.sort_by.with_index { |item, index| [item.position.to_i, index] }
  end

  # The "Add from template" menu: [category name or nil, templates] pairs,
  # uncategorized first, then by category order.
  def expert_checklist_template_groups(issue)
    return [] unless issue.project

    templates = ExpertChecklistTemplate.available_for(issue.project, issue.tracker).
      includes(:category).sorted.to_a
    templates.group_by(&:category).sort_by do |category, _|
      category ? [1, category.position.to_i, category.name.to_s] : [0, 0, '']
    end.map { |category, list| [category && category.name, list] }
  end

  # Template id => item rows, read by the editor script.
  def expert_checklist_templates_json(groups)
    groups.flat_map(&:last).each_with_object({}) { |template, map| map[template.id] = template.rows }.to_json
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
        :templateAdded => l(:text_expert_checklist_template_added),
        :saveFailed => l(:error_expert_checklist_save_failed),
        :hideDone => l(:label_expert_checklist_hide_done),
        :showDone => l(:label_expert_checklist_show_done)
      }
    }
  end
end
