require File.expand_path('../../test_helper', __FILE__)

# The issue page block, the form editor and checklist edits saved with the form.
class IssuesControllerChecklistTest < Redmine::ControllerTest
  include ExpertChecklistsTestHelper
  tests IssuesController

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :projects_trackers, :enumerations,
           :enabled_modules, :journals, :journal_details, :watchers, :workflows,
           :issue_categories, :versions, :custom_fields, :custom_values, :custom_fields_projects,
           :custom_fields_trackers, :attachments

  def setup
    enable_checklists
    use_test_job_adapter
    @issue = Issue.find(1)
    @items = add_items(@issue, '-- Prep', '[x] Buy milk', 'Bake <bread>')
    @request.session[:user_id] = 2
    ActionMailer::Base.deliveries.clear
  end

  def teardown
    restore_job_adapter
  end

  def rows(*rows)
    rows.each_with_index.to_h { |row, index| [index.to_s, row] }
  end

  def test_show_renders_the_checklist_block
    get :show, :params => { :id => 1 }
    assert_response :success
    assert_select 'div.expert-checklist[data-ec-list]' do
      assert_select 'li.ec-section', :text => 'Prep'
      assert_select 'li.ec-item.ec-done input.ec-check[checked]', 1
      assert_select 'li.ec-item span.ec-subject', :text => 'Bake <bread>'
      assert_select '.ec-progress', :text => '1/2'
    end
    assert_select 'script.ec-config[type="application/json"]'
    assert_select '[data-ec-editor] ul.ec-edit-items > li[data-ec-row]', 3
  end

  def test_show_renders_nothing_while_the_module_is_off
    Project.find(1).disable_module!(:expert_checklists)
    get :show, :params => { :id => 1 }
    assert_select 'div.expert-checklist', 0
    assert_select '[data-ec-editor]', 0
  end

  def test_show_without_view_permission
    Role.find(1).remove_permission!(:view_expert_checklists)
    get :show, :params => { :id => 1 }
    assert_select 'div.expert-checklist', 0
  end

  def test_update_journalizes_checklist_changes_with_the_edit_and_mails_once
    Role.all.each { |role| role.add_permission!(:view_expert_checklists) }
    put :update, :params => {
      :id => 1,
      :issue => {
        :notes => 'Shopping done',
        :expert_checklist_form => '1',
        :expert_checklist_items_attributes => rows(
          { :id => @items[0].id, :subject => 'Prep', :subject_was => 'Prep', :is_section => '1' },
          { :id => @items[2].id, :subject => 'Bake bread', :subject_was => 'Bake <bread>',
            :is_done => '1', :is_done_was => '0' },
          { :id => @items[1].id, :_destroy => '1' },
          { :subject => 'Clean up' }
        )
      }
    }
    assert_response :redirect

    @issue.reload
    assert_equal ['Prep', 'Bake bread', 'Clean up'], @issue.expert_checklist_items.map(&:subject)
    assert_equal [1, 2, 3], @issue.expert_checklist_items.map(&:position)
    journal = @issue.journals.last
    assert_equal 'Shopping done', journal.notes
    assert_equal 3, checklist_details(journal).size
    assert_equal 0, ExpertChecklistNotification.count
    assert_equal 1, ActionMailer::Base.deliveries.map(&:subject).uniq.size
    assert ActionMailer::Base.deliveries.any? { |mail| mail.text_part.body.to_s.include?('Checklist item Clean up added') }
  end

  def test_checklist_only_edit_creates_a_journal
    assert_difference 'Journal.count', 1 do
      put :update, :params => {
        :id => 1,
        :issue => { :expert_checklist_form => '1',
                    :expert_checklist_items_attributes => rows({ :subject => 'New one' }) }
      }
    end
    assert_equal 1, checklist_details(Journal.last).size
  end

  def test_unchanged_fields_do_not_revert_a_concurrent_tick
    # Somebody ticked "Bake" after this form was rendered.
    @items[2].update!(:is_done => true)
    put :update, :params => {
      :id => 1,
      :issue => {
        :notes => 'x',
        :expert_checklist_items_attributes => rows(
          { :id => @items[2].id, :subject => 'Bake <bread>', :subject_was => 'Bake <bread>',
            :is_done => '0', :is_done_was => '0' }
        )
      }
    }
    assert @items[2].reload.is_done?
  end

  def test_rows_of_items_deleted_meanwhile_are_ignored
    gone = @items[2].id
    @items[2].destroy
    put :update, :params => {
      :id => 1,
      :issue => { :notes => 'x', :expert_checklist_items_attributes => rows({ :id => gone, :subject => 'y' }) }
    }
    assert_response :redirect
  end

  def test_nested_attributes_need_the_edit_permission
    Role.find(1).remove_permission!(:edit_expert_checklists)
    put :update, :params => {
      :id => 1,
      :issue => { :notes => 'x', :expert_checklist_items_attributes => rows({ :subject => 'Sneaky' }) }
    }
    assert_not @issue.reload.expert_checklist_items.map(&:subject).include?('Sneaky')
  end

  def test_closing_is_blocked_while_items_are_open
    with_checklist_settings('block_issue_closing' => '1') do
      put :update, :params => { :id => 1, :issue => { :status_id => 5 } }
      assert_response :success
      assert_select '#errorExplanation', :text => /checklist items are open/
      assert_not @issue.reload.closed?

      put :update, :params => {
        :id => 1,
        :issue => { :status_id => 5,
                    :expert_checklist_items_attributes => rows(
                      { :id => @items[2].id, :is_done => '1', :is_done_was => '0' }
                    ) }
      }
      assert @issue.reload.closed?
    end
  end

  def test_done_ratio_follows_the_form
    with_settings(:issue_done_ratio => 'issue_field') do
      with_checklist_settings('done_ratio_from_checklist' => '1') do
        put :update, :params => {
          :id => 1,
          :issue => { :expert_checklist_items_attributes => rows(
            { :id => @items[2].id, :is_done => '1', :is_done_was => '0' }
          ) }
        }
        assert_equal 100, @issue.reload.done_ratio
      end
    end
  end

  def test_new_copy_form_is_prefilled_from_the_source
    get :new, :params => { :project_id => 1, :copy_from => 1 }
    assert_response :success
    assert_select '[data-ec-editor] ul.ec-edit-items > li[data-ec-row] input.ec-subject-input[value=?]', 'Bake <bread>'
    assert_select '[data-ec-editor] ul.ec-edit-items > li[data-ec-row] input[data-ec-field="id"]', 0
  end

  def test_copy_without_form_rows_copies_the_items
    User.current = User.find(2)
    copy = @issue.copy
    copy.save!
    assert_equal ['Prep', 'Buy milk', 'Bake <bread>'], copy.reload.expert_checklist_items.map(&:subject)
    assert copy.expert_checklist_items[1].is_done?
  end
end
