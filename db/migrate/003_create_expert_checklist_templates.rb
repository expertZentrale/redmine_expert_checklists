# Checklist templates: reusable item lists, global (project_id NULL, admins) or
# of a project, public or private to their author, optionally the default for
# new issues (of one tracker or of all). Items are text, one per line - "-- "
# starts a section, "[x] " a done item - the format the editor's paste takes.
# Categories group templates in the editor's menu.
class CreateExpertChecklistTemplates < ActiveRecord::Migration[6.1]
  def change
    create_table :expert_checklist_template_categories do |t|
      t.string :name, :null => false
      t.integer :position
    end

    create_table :expert_checklist_templates do |t|
      t.string :name, :null => false
      t.integer :project_id
      t.integer :category_id
      t.integer :tracker_id
      t.integer :author_id
      t.boolean :is_public, :null => false, :default => true
      t.boolean :is_default, :null => false, :default => false
      t.text :items
      t.timestamps :null => true
    end
    add_index :expert_checklist_templates, [:project_id, :tracker_id]
    add_index :expert_checklist_templates, :category_id
  end
end
