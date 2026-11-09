module RedmineExpertChecklists
  # Renders checklist history lines: our own per-item details and, once
  # RedmineUP Checklists is gone (from the issue's project or altogether), the
  # snapshot details it left behind. Returns
  # one string per change, so the history shows one list entry per item.
  #
  # Called from IssuesHelperPatch#details_to_strings, which every history view,
  # notification mail, PDF export and the journals Atom feed go through.
  module DetailRenderer
    module_function

    # issue: the issue the detail belongs to, needed for RedmineUP's details
    # while it is installed.
    def handles?(detail, issue = nil)
      detail.property == DETAIL_PROPERTY || legacy?(detail, issue)
    end

    # RedmineUP renders its own details where it is still in use and drops them
    # where it is switched off, so they are ours once it is gone or once the
    # issue's project has changed over to our module.
    def legacy?(detail, issue = nil)
      detail.property == 'attr' && detail.prop_key == 'checklist' &&
        !RedmineExpertChecklists.legacy_live?(issue && issue.project)
    end

    # The issue a list of details belongs to: the journal's when it is at hand,
    # else the one the view or mail renders (@issue). Only asked when it
    # matters: RedmineUP installed and one of its details in the list.
    def issue_for(details, current = nil)
      return current unless RedmineExpertChecklists.redmineup_present?

      detail = details.detect { |d| d.property == 'attr' && d.prop_key == 'checklist' }
      return current unless detail
      return current if current.is_a?(Issue) && !detail.association(:journal).loaded?

      journal = detail.journal
      journal && journal.journalized_type == 'Issue' ? journal.journalized : current
    end

    def strings(detail, no_html = false)
      if detail.property == DETAIL_PROPERTY
        item_lines(parse_snapshot(detail.old_value), parse_snapshot(detail.value), no_html)
      else
        legacy_lines(detail, no_html)
      end
    end

    def item_lines(old, new, no_html)
      return [] if old.nil? && new.nil?
      return [line(new['is_section'] ? :section_added : :item_added, no_html, :subject => new['subject'])] if old.nil?
      return [line(old['is_section'] ? :section_deleted : :item_deleted, no_html, :subject => old['subject'])] if new.nil?

      lines = []
      if old['is_section'] != new['is_section']
        lines << line(new['is_section'] ? :item_to_section : :section_to_item, no_html, :subject => new['subject'])
      end
      if old['subject'] != new['subject']
        lines << line(new['is_section'] ? :section_renamed : :item_renamed, no_html,
                      :old => old['subject'], :new => new['subject'])
      end
      if old['is_done'] != new['is_done'] && !new['is_section']
        lines << line(new['is_done'] ? :item_done : :item_undone, no_html, :subject => new['subject'])
      end
      lines
    end

    def legacy_lines(detail, no_html)
      before, after = legacy_snapshots(detail)
      if before.nil? || after.nil? ||
         LegacyDiff.old_text_format?(detail.old_value) || LegacyDiff.old_text_format?(detail.value)
        return [changed_line(detail.old_value, detail.value, no_html)]
      end

      lines = (before.keys | after.keys).flat_map { |key| item_lines(before[key], after[key], no_html) }
      # RedmineUP journaled reorders too; the snapshots then differ only in order.
      lines.empty? ? [line(:reordered, no_html)] : lines
    end

    # Matched by id. Rows without one (RedmineUP's custom-field format) would
    # all share the empty key, so then both sides are matched by subject.
    def legacy_snapshots(detail)
      before = LegacyDiff.parse(detail.old_value)
      after = LegacyDiff.parse(detail.value)
      if [before, after].any? { |map| map && map.key?('') }
        before = LegacyDiff.parse(detail.old_value, :subject)
        after = LegacyDiff.parse(detail.value, :subject)
      end
      [before, after]
    end

    def parse_snapshot(value)
      return nil if value.nil? || value.to_s.empty?

      data = JSON.parse(value.to_s)
      data.is_a?(Hash) ? data : nil
    rescue JSON::ParserError
      nil
    end

    def line(key, no_html, values = {})
      label = ::I18n.t(:label_expert_checklist)
      if no_html
        ::I18n.t("text_expert_checklist_#{key}", **values.merge(:label => label))
      else
        values = values.transform_values { |value| "<i>#{ERB::Util.h(value)}</i>" }
        ::I18n.t("text_expert_checklist_#{key}",
                 **values.merge(:label => "<strong>#{ERB::Util.h(label)}</strong>")).html_safe
      end
    end

    # Fallback for values that are not JSON lists (very old RedmineUP data):
    # core's own "changed from ... to ..." wording.
    def changed_line(old_value, value, no_html)
      label = ::I18n.t(:label_expert_checklist)
      if no_html
        ::I18n.t(:text_journal_changed, :label => label, :old => old_value.to_s, :new => value.to_s)
      else
        ::I18n.t(:text_journal_changed, :label => "<strong>#{ERB::Util.h(label)}</strong>",
                                        :old => "<i>#{ERB::Util.h(old_value)}</i>",
                                        :new => "<i>#{ERB::Util.h(value)}</i>").html_safe
      end
    end
  end
end
