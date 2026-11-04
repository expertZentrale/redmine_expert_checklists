# Checklist items of an issue. Sections are rows with is_section set; they have
# no checkbox and never count towards progress. Positions are dense per issue
# (1..n), rewritten on reorder; reads order by position, then id.
class CreateExpertChecklistItems < ActiveRecord::Migration[6.1]
  def change
    create_table :expert_checklist_items do |t|
      t.integer :issue_id, :null => false
      t.string :subject, :limit => 1000, :null => false
      t.boolean :is_done, :null => false, :default => false
      t.boolean :is_section, :null => false, :default => false
      t.integer :position, :null => false, :default => 1
      # created_at/updated_at rather than Redmine's created_on: the REST API keeps
      # the field names RedmineUP Checklists clients already read.
      t.timestamps :null => true
    end
    add_index :expert_checklist_items, [:issue_id, :position]
    # Covers the EXISTS subqueries of the issue list filters.
    add_index :expert_checklist_items, [:issue_id, :is_done, :is_section],
              :name => 'index_expert_checklist_items_on_issue_done_section'
  end
end
