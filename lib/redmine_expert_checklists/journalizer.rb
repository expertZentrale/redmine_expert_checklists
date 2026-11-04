module RedmineExpertChecklists
  # Turns two checklist states (item id => snapshot, see
  # RedmineExpertChecklists.snapshots_for) into history details: one per item
  # whose subject, done state or section flag differs. Positions are not part of
  # the snapshot, so reordering alone writes no history.
  module Journalizer
    Change = Struct.new(:prop_key, :old_value, :value)

    module_function

    def diff(before, after)
      ids = (before.keys | after.keys).sort
      ids.each_with_object([]) do |id, changes|
        old = before[id]
        new = after[id]
        next if old == new

        changes << Change.new(id.to_s, RedmineExpertChecklists.dump(old), RedmineExpertChecklists.dump(new))
      end
    end

    def detail_for(change)
      JournalDetail.new(:property => DETAIL_PROPERTY, :prop_key => change.prop_key,
                        :old_value => change.old_value, :value => change.value)
    end
  end
end
