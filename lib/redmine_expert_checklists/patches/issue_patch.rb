module RedmineExpertChecklists
  module Patches
    # Checklist items on Issue: the association, the issue form's nested
    # attributes, history for checklist edits saved with the form, done ratio,
    # blocking the close, and copying.
    #
    # The form path differs from a tick on the issue page on purpose: a form save
    # is one deliberate change, so its checklist edits go into core's journal of
    # that save and core mails it right away, together with notes and field
    # changes. Ticks are bundled by Recorder.
    module IssuePatch
      def self.apply!(base = Issue)
        return if base.included_modules.include?(InstanceMethods)

        base.send(:include, InstanceMethods)
        base.class_eval do
          has_many :expert_checklist_items, lambda { order(:position, :id) },
                   :class_name => 'ExpertChecklistItem', :dependent => :delete_all,
                   :inverse_of => :issue
          accepts_nested_attributes_for :expert_checklist_items, :allow_destroy => true

          safe_attributes 'expert_checklist_items_attributes', 'expert_checklist_form',
                          :if => lambda { |issue, user| RedmineExpertChecklists.editable?(issue, user) }

          before_save :expert_checklists_update_done_ratio
          validate :expert_checklists_block_closing
          after_save :expert_checklists_after_save
        end

        # RedmineUP's attribute name, for API clients written against it. Only
        # without RedmineUP: its own has_many :checklists owns the name then.
        unless RedmineExpertChecklists.redmineup_present? || base.method_defined?(:checklists_attributes=)
          base.send(:include, RedmineUpCompat)
          base.safe_attributes 'checklists_attributes',
                               :if => lambda { |issue, user| RedmineExpertChecklists.editable?(issue, user) }
        end
      end

      module RedmineUpCompat
        def checklists_attributes=(attributes)
          self.expert_checklist_items_attributes = attributes
        end
      end

      module InstanceMethods
        # Sent by the form editor, so an edit that removes every item (or a copy
        # form whose items were all removed) still counts as "items given".
        def expert_checklist_form=(_value)
          @expert_checklist_form = true
        end

        def expert_checklist_form
          @expert_checklist_form ? '1' : nil
        end

        # The issue this one is being copied from (issues/new?copy_from=...).
        def expert_checklists_copy_source
          @copied_from
        end

        # Value of the "Checklist" issue list column; nil when empty or not
        # visible to the current user.
        def expert_checklist
          return nil unless RedmineExpertChecklists.viewable?(self)

          items = @expert_checklist_preloaded || expert_checklist_items.to_a
          items.empty? ? nil : RedmineExpertChecklists::ListValue.new(items)
        end

        # Set by IssueQueryPatch.preload: one query for a whole list page.
        def expert_checklist_preloaded=(items)
          @expert_checklist_preloaded = items
        end

        # Rows come from the form editor in display order (positions are taken
        # from that order) or from the API. The editor also sends subject_was and
        # is_done_was, the values it was rendered with: a field is only written
        # when the user changed it, so a tick somebody else made while this form
        # was open is not reverted. Rows for items deleted in the meantime are
        # dropped instead of failing the whole save.
        def expert_checklist_items_attributes=(attributes)
          @expert_checklist_form = true
          existing = new_record? ? {} : expert_checklist_items.index_by(&:id)
          @expert_checklists_before ||= existing.transform_values(&:snapshot) unless new_record?

          position = 0
          rows = RedmineExpertChecklists::Patches::IssuePatch.normalize_rows(attributes).map do |row|
            destroy = RedmineExpertChecklists::LegacyDiff.truthy?(row['_destroy'])
            if row['id'].present?
              next nil unless existing[row['id'].to_i]
              next({ 'id' => row['id'].to_s, '_destroy' => '1' }) if destroy

              attrs = { 'id' => row['id'].to_s }
              %w(subject is_done is_section).each do |name|
                next unless row.key?(name)
                next if row.key?("#{name}_was") && row[name].to_s == row["#{name}_was"].to_s

                attrs[name] = row[name]
              end
            else
              next nil if destroy || row['subject'].to_s.strip.empty?

              attrs = row.slice('subject', 'is_done', 'is_section')
            end
            position += 1
            attrs.merge('position' => position)
          end
          super(rows.compact)
        end

        private

        def expert_checklists_update_done_ratio
          return unless @expert_checklist_form && RedmineExpertChecklists.enabled?(project)
          return unless RedmineExpertChecklists.done_ratio_applies?(self)

          ratio = RedmineExpertChecklists.done_ratio_for(expert_checklist_items.reject(&:marked_for_destruction?))
          self.done_ratio = ratio if ratio
        end

        # Only on the transition to closed: notes on an issue that is already
        # closed (mail replies included) must not fail.
        def expert_checklists_block_closing
          return unless RedmineExpertChecklists.setting_on?(:block_issue_closing)
          return unless closing? && RedmineExpertChecklists.enabled?(project)

          open = expert_checklist_items.reject(&:marked_for_destruction?).any? do |item|
            !item.is_section? && !item.is_done?
          end
          errors.add(:base, ::I18n.t(:error_expert_checklist_open_items)) if open
        end

        def expert_checklists_after_save
          if saved_change_to_id?
            expert_checklists_copy_from_source
          else
            expert_checklists_journalize
          end
        end

        # Runs after core's create_journal (an earlier after_save). If core saved
        # the journal, our details are added to it (<< saves them); if it was
        # empty and therefore not saved, saving it now creates it. Either way
        # core's after_create_commit mails the whole edit as one notification.
        def expert_checklists_journalize
          before = @expert_checklists_before
          @expert_checklists_before = nil
          journal = current_journal
          return unless before && journal

          changes = RedmineExpertChecklists::Journalizer.diff(before, RedmineExpertChecklists.snapshots_for(id))
          return if changes.empty?

          changes.each { |change| journal.details << RedmineExpertChecklists::Journalizer.detail_for(change) }
          RedmineExpertChecklists::Patches::IssuePatch.adjust_notification(journal)
          journal.save if journal.new_record?
        end

        # Bulk copy, project copy and subtask copies carry no form rows; copy the
        # source's items. A copy made through the form brings its own rows.
        def expert_checklists_copy_from_source
          source = @copied_from
          return if @expert_checklist_form || source.nil? || source.id.nil?
          return unless RedmineExpertChecklists.enabled?(project)

          source.expert_checklist_items.each do |item|
            ExpertChecklistItem.create!(:issue_id => id, :subject => item.subject, :is_done => item.is_done,
                                        :is_section => item.is_section, :position => item.position)
          end
          expert_checklist_items.reset
        end
      end

      def self.normalize_rows(attributes)
        attributes = attributes.to_unsafe_h if attributes.respond_to?(:to_unsafe_h)
        rows = attributes.is_a?(Hash) ? attributes.sort_by { |key, _| key.to_s.to_i }.map(&:last) : Array(attributes)
        rows.select { |row| row.respond_to?(:to_h) || row.respond_to?(:to_unsafe_h) }.map do |row|
          row = row.to_unsafe_h if row.respond_to?(:to_unsafe_h)
          row.to_h.transform_keys(&:to_s)
        end
      end

      # The notifications setting applies to form saves that change nothing but
      # the checklist (and the done ratio it drives): "never" keeps core from
      # mailing them, "always" mails them even when issue updates are not mailed.
      def self.adjust_notification(journal)
        return unless journal.notes.blank?
        return unless journal.details.all? do |detail|
          detail.property == DETAIL_PROPERTY || (detail.property == 'attr' && detail.prop_key == 'done_ratio')
        end

        case RedmineExpertChecklists.notification_mode
        when 'never'
          journal.notify = false
        when 'always'
          journal.instance_variable_set(:@expert_checklists_force_mail, true)
        end
      end
    end
  end
end
