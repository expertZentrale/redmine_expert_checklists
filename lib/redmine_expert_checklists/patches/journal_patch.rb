module RedmineExpertChecklists
  module Patches
    # Hides checklist history from users without the view permission. Core's
    # visible_details decides what the history tab shows, what a notification
    # mail lists and whether a user is mailed at all (Mailer.deliver_issue_edit
    # skips recipients with no visible detail), and what the REST API returns.
    #
    # Prepended: nobody installed alongside aliases visible_details.
    module JournalPatch
      def self.apply!(base = Journal)
        return if base.ancestors.include?(self)

        base.prepend(self)
        base.after_create_commit :expert_checklists_forced_mail
      end

      def visible_details(user = User.current)
        details = super
        return details unless journalized_type == 'Issue'
        return details unless details.any? { |detail| RedmineExpertChecklists::DetailRenderer.handles?(detail) }
        return details if RedmineExpertChecklists.viewable?(journalized, user)

        details.reject { |detail| RedmineExpertChecklists::DetailRenderer.handles?(detail) }
      end

      private

      # Notification setting "always": a form save that changed only the
      # checklist is mailed even when Redmine does not mail issue updates (core's
      # send_notification then skips it). Flag set by IssuePatch.
      def expert_checklists_forced_mail
        return unless @expert_checklists_force_mail && notify?
        return if Setting.notified_events.include?('issue_updated')

        Mailer.deliver_issue_edit(self)
      end
    end
  end
end
