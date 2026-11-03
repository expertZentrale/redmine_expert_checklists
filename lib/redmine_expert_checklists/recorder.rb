module RedmineExpertChecklists
  # Records direct checklist changes (a tick on the issue page, REST calls) in
  # the issue history and schedules one bundled mail.
  #
  #   Recorder.call(issue, user) { item.update!(:is_done => true) }
  #
  # The block runs inside one transaction with the issue row locked, so two
  # clicks on the same issue never interleave. Afterwards:
  # - the items before and after are compared (Journalizer);
  # - the done ratio follows the checklist when that setting applies;
  # - the changes are merged into the user's previous checklist journal when
  #   that is still the issue's last journal and its mail has not gone out
  #   (ExpertChecklistNotification row still pending); otherwise a new journal
  #   is written with core's immediate mail switched off;
  # - the mail job is scheduled for the end of the bundle window.
  #
  # RedmineUP Checklists mailed every recipient synchronously inside the
  # request, which made a click take seconds; here the request sends nothing.
  class Recorder
    BUNDLE_WINDOW = 60.seconds
    # A journal stops absorbing clicks this long after it was written, so one
    # mail never stands for an afternoon of ticking.
    MAX_BUNDLE_SPAN = 10.minutes

    def self.call(issue, user = User.current, &block)
      new(issue, user).call(&block)
    end

    def initialize(issue, user)
      @issue = issue
      @user = user
    end

    # Returns the journal the changes went to, or nil when nothing changed in
    # the end (no history entry, no mail).
    def call
      scheduled = nil
      journal = nil
      Issue.transaction do
        # Serializes writers of this issue (double clicks, two pods).
        Issue.where(:id => @issue.id).lock.pluck(:id)
        before = RedmineExpertChecklists.snapshots_for(@issue.id)
        yield
        after = RedmineExpertChecklists.snapshots_for(@issue.id)

        details = Journalizer.diff(before, after).map { |change| Journalizer.detail_for(change) }
        next if details.empty?

        ratio_detail = update_done_ratio(after.values)
        details << ratio_detail if ratio_detail
        journal, scheduled = record(details)
      end
      ExpertChecklistNotification.enqueue(*scheduled) if scheduled
      ExpertChecklistNotification.sweep_if_due
      journal
    end

    private

    # Saves the issue so core updates updated_on, the parent's derived ratio and
    # lock_version, but adds the attribute change to our journal itself.
    def update_done_ratio(items)
      unless RedmineExpertChecklists.done_ratio_applies?(@issue)
        touch_issue
        return nil
      end

      ratio = RedmineExpertChecklists.done_ratio_for(items)
      @issue.reload
      old_ratio = @issue.done_ratio
      if ratio.nil? || ratio == old_ratio
        touch_issue
        return nil
      end

      @issue.done_ratio = ratio
      @issue.save(:validate => false)
      JournalDetail.new(:property => 'attr', :prop_key => 'done_ratio',
                        :old_value => old_ratio.to_s, :value => ratio.to_s)
    end

    # A checklist change is an issue change: lists sorted by "Updated" should
    # show it. update_all leaves lock_version alone, so an edit form the user
    # still has open does not turn stale.
    def touch_issue
      Issue.where(:id => @issue.id).update_all(:updated_on => Time.now)
    end

    # Returns [journal, [journal_id, revision, due_at]] or [nil, nil] when a
    # merge cancelled out (tick and untick within the window).
    def record(details)
      now = Time.now
      last_id = Journal.where(:journalized_type => 'Issue', :journalized_id => @issue.id).maximum(:id)
      if last_id && claim_merge(last_id, now)
        merge(Journal.find(last_id), details)
      else
        create(details, now)
      end
    end

    # Pushes the pending mail of last_id back by one window, provided it is ours
    # and still pending. Exactly one of this UPDATE and the job's claiming
    # DELETE wins the row.
    def claim_merge(journal_id, now)
      ExpertChecklistNotification.
        where(:journal_id => journal_id, :user_id => @user.id).
        where('due_at > ? AND created_at > ?', now, now - MAX_BUNDLE_SPAN).
        update_all(['revision = revision + 1, due_at = ?, updated_at = ?', now + BUNDLE_WINDOW, now]) == 1
    end

    def merge(journal, details)
      existing = journal.details.to_a
      details.each do |detail|
        match = existing.detect { |d| d.property == detail.property && d.prop_key == detail.prop_key }
        if match.nil?
          journal.details.create!(:property => detail.property, :prop_key => detail.prop_key,
                                  :old_value => detail.old_value, :value => detail.value)
        elsif match.old_value.to_s == detail.value.to_s
          match.delete
        else
          match.update_columns(:value => detail.value)
        end
      end

      row = ExpertChecklistNotification.find_by(:journal_id => journal.id)
      if journal.details.reload.empty?
        # Ticked and unticked again: no history, no mail.
        row.delete if row
        journal.delete
        return [nil, nil]
      end
      [journal, [journal.id, row.revision, row.due_at]]
    end

    def create(details, now)
      journal = Journal.new(:journalized => @issue, :user => @user, :notes => '')
      # Core would mail right after the commit; the bundled mail replaces that.
      journal.notify = false
      details.each { |detail| journal.details << detail }
      raise ActiveRecord::RecordNotSaved.new('checklist journal not saved', journal) unless journal.save

      due_at = now + BUNDLE_WINDOW
      ExpertChecklistNotification.create!(:journal_id => journal.id, :issue_id => @issue.id,
                                          :user_id => @user.id, :revision => 1, :due_at => due_at)
      [journal, [journal.id, 1, due_at]]
    end
  end
end
