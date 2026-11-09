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

  def test_show_without_a_checklist_permission
    revoke_checklists
    get :show, :params => { :id => 1 }
    assert_select 'div.expert-checklist', 0
  end

  def test_show_with_the_tick_permission_only
    Role.find(1).remove_permission!(:view_expert_checklists)
    Role.find(1).remove_permission!(:edit_expert_checklists)
    get :show, :params => { :id => 1 }
    assert_select 'div.expert-checklist input.ec-check:not([disabled])'
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

  # Core saves the journal before our after_save (it already holds the done
  # ratio detail), so "never" must still work on a persisted journal: notify is
  # an in-memory flag that core's after_create_commit reads from this object.
  def test_never_mode_suppresses_the_mail_of_an_already_saved_journal
    Role.all.each { |role| role.add_permission!(:view_expert_checklists) }
    with_settings(:issue_done_ratio => 'issue_field', :notified_events => %w(issue_updated)) do
      with_checklist_settings('done_ratio_from_checklist' => '1', 'notifications' => 'never') do
        put :update, :params => {
          :id => 1,
          :issue => { :expert_checklist_form => '1', :expert_checklist_items_attributes => rows(
            { :id => @items[2].id, :is_done => '1', :is_done_was => '0' }
          ) }
        }
      end
    end
    journal = @issue.reload.journals.last
    assert_equal %w(done_ratio), journal.details.select { |d| d.property == 'attr' }.map(&:prop_key)
    assert journal.details.any? { |d| d.property == RedmineExpertChecklists::DETAIL_PROPERTY }
    assert_empty ActionMailer::Base.deliveries
  end

  # Rows go through our setter (positions, *_was, dropped rows), not the one
  # accepts_nested_attributes_for generated: ours is included later.
  def test_our_nested_attributes_setter_takes_precedence
    assert_equal RedmineExpertChecklists::Patches::IssuePatch::InstanceMethods,
                 Issue.instance_method(:expert_checklist_items_attributes=).owner
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

  def test_copy_from_a_project_still_on_redmineup_takes_its_rows
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    ActiveRecord::Base.connection.execute('DELETE FROM checklists')
    source = Issue.where.not(:project_id => 1).first
    assert_not RedmineExpertChecklists.enabled?(source.project)
    insert_legacy_item(9101, source.id, 'From RedmineUP', true, 1)
    insert_legacy_item(9102, source.id, 'Second', false, 2)
    ExpertChecklistItem.create!(:issue_id => source.id, :subject => 'stale copy')

    User.current = User.find(1)
    copy = Issue.new.copy_from(source)
    copy.project = Project.find(1)
    copy.assigned_to = nil
    copy.author = User.find(2)
    copy.save!
    assert_equal ['From RedmineUP', 'Second'], copy.reload.expert_checklist_items.map(&:subject)
    assert copy.expert_checklist_items.first.is_done?
  end

  def add_default_template(attributes = {})
    add_template({ :name => 'Bug default', :items => "-- Check\nReproduce\nFix", :is_default => true,
                   :tracker_id => 1 }.merge(attributes))
  end

  def default_rows
    { '0' => { 'subject' => 'Check', 'is_section' => '1' }, '1' => { 'subject' => 'Reproduce' },
      '2' => { 'subject' => 'Fix' } }
  end

  def test_new_form_starts_with_the_default_template
    template = add_default_template
    get :new, :params => { :project_id => 1, :issue => { :tracker_id => 1 } }
    assert_response :success
    assert_select '[data-ec-editor] input.ec-subject-input[value=?]', 'Reproduce'
    assert_select '[data-ec-editor] input[name=?][value=?]', 'issue[expert_checklist_template_id]', template.id.to_s
  end

  def test_untouched_default_follows_a_tracker_change
    bug = add_default_template
    add_default_template(:tracker_id => 2, :name => 'Feature default', :items => "Spec\nBuild")
    post :new, :params => { :project_id => 1, :format => 'js',
                            :issue => { :tracker_id => 2, :expert_checklist_form => '1',
                                        :expert_checklist_template_id => bug.id.to_s,
                                        :expert_checklist_items_attributes => default_rows } }, :xhr => true
    assert_response :success
    assert_include 'value=\\"Spec\\"', response.body
    assert_not_include 'value=\\"Reproduce\\"', response.body
  end

  def test_edited_default_stays_on_a_tracker_change
    bug = add_default_template
    add_default_template(:tracker_id => 2, :name => 'Feature default', :items => "Spec\nBuild")
    rows = default_rows.merge('3' => { 'subject' => 'Mine' })
    post :new, :params => { :project_id => 1, :format => 'js',
                            :issue => { :tracker_id => 2, :expert_checklist_form => '1',
                                        :expert_checklist_template_id => bug.id.to_s,
                                        :expert_checklist_items_attributes => rows } }, :xhr => true
    assert_response :success
    assert_include 'value=\\"Mine\\"', response.body
    assert_include 'value=\\"Reproduce\\"', response.body
    assert_not_include 'value=\\"Spec\\"', response.body
  end

  def test_create_without_checklist_rows_starts_with_the_default
    add_default_template
    # dlopper (Developer) may add issues but has no checklist permission: no editor, no rows.
    @request.session[:user_id] = 3
    post :create, :params => { :project_id => 1, :issue => { :tracker_id => 1, :subject => 'No editor' } }
    issue = Issue.order(:id).last
    assert_equal 'No editor', issue.subject
    assert_equal %w(Check Reproduce Fix), issue.expert_checklist_items.map(&:subject)
  end

  def test_create_with_an_emptied_editor_gets_no_default
    add_default_template
    post :create, :params => { :project_id => 1,
                               :issue => { :tracker_id => 1, :subject => 'Emptied', :expert_checklist_form => '1' } }
    issue = Issue.order(:id).last
    assert_equal 'Emptied', issue.subject
    assert_empty issue.expert_checklist_items.to_a
  end

  def test_template_menu_lists_the_available_templates
    add_template(:name => 'Release steps', :items => "Tag\nAnnounce")
    add_template(:name => 'Other tracker', :tracker_id => 2)
    get :new, :params => { :project_id => 1, :issue => { :tracker_id => 1 } }
    assert_select '[data-ec-editor] select.ec-template option', :text => 'Release steps'
    assert_select '[data-ec-editor] select.ec-template option', :text => 'Other tracker', :count => 0
    assert_select '[data-ec-editor] script.ec-templates'
  end

  def test_template_text_cannot_break_out_of_its_script_element
    add_template(:name => 'Nasty', :items => "</script><script>alert(1)</script>")
    get :new, :params => { :project_id => 1, :issue => { :tracker_id => 1 } }
    assert_response :success
    assert_not_include '</script><script>alert(1)', response.body
    assert_include '\\u003c/script\\u003e', response.body
  end

  def test_default_template_sets_the_done_ratio
    add_default_template(:items => "[x] Reproduce\nFix")
    @request.session[:user_id] = 3
    with_settings(:issue_done_ratio => 'issue_field') do
      with_checklist_settings(:done_ratio_from_checklist => '1') do
        post :create, :params => { :project_id => 1, :issue => { :tracker_id => 1, :subject => 'Half done' } }
      end
    end
    assert_equal 50, Issue.order(:id).last.done_ratio
  end
end
