# Pending notification mails for checklist journals (see
# RedmineExpertChecklists::Recorder). Ticks by the same user within a minute are
# merged into one journal; its mail goes out once due_at has passed. The row is
# the durable record: the job that sends it lives in memory and is lost on a
# restart, so a sweeper re-enqueues overdue rows.
class CreateExpertChecklistNotifications < ActiveRecord::Migration[6.1]
  def change
    create_table :expert_checklist_notifications do |t|
      t.integer :journal_id, :null => false
      t.integer :issue_id, :null => false
      t.integer :user_id, :null => false
      # Bumped by every merge; a job only sends the revision it was enqueued for.
      t.integer :revision, :null => false, :default => 1
      t.datetime :due_at, :null => false
      t.timestamps :null => true
    end
    add_index :expert_checklist_notifications, :journal_id, :unique => true
    add_index :expert_checklist_notifications, :due_at
  end
end
