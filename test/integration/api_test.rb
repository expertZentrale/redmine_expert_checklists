require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistsApiTest < Redmine::ApiTest::Base
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :projects_trackers, :enumerations,
           :enabled_modules, :journals, :journal_details, :watchers, :workflows

  def setup
    super
    enable_checklists
    use_test_job_adapter
    @issue = Issue.find(1)
    @items = add_items(@issue, '-- Prep', 'Buy milk')
  end

  def teardown
    restore_job_adapter
    super
  end

  def test_index_lists_items_with_redmineup_field_names
    get '/issues/1/expert_checklist_items.json', :headers => credentials('jsmith')
    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal 2, json['total_count']
    item = json['checklists'][1]
    assert_equal %w(created_at id is_done is_section issue_id position subject updated_at), item.keys.sort
    assert_equal 'Buy milk', item['subject']
    assert_equal true, json['checklists'][0]['is_section']
  end

  def test_index_xml
    get '/issues/1/expert_checklist_items.xml', :headers => credentials('jsmith')
    assert_response :success
    assert_select 'checklists[type=array][total_count="2"] checklist subject', :text => 'Buy milk'
  end

  def test_create_update_destroy_are_journaled_and_bundled
    assert_difference 'Journal.count', 1 do
      post '/issues/1/expert_checklist_items.json',
           :params => { :checklist => { :subject => 'Clean up' } }, :headers => credentials('jsmith')
      assert_response :created
      id = ActiveSupport::JSON.decode(response.body)['checklist']['id']
      assert_equal 3, ExpertChecklistItem.find(id).position

      put "/expert_checklist_items/#{id}.json",
          :params => { :checklist => { :is_done => true } }, :headers => credentials('jsmith')
      assert_response :no_content

      delete "/expert_checklist_items/#{@items[1].id}.json", :headers => credentials('jsmith')
      assert_response :no_content
    end
    assert_equal 2, checklist_details(Journal.last).size
  end

  def test_create_validation_error
    post '/issues/1/expert_checklist_items.json',
         :params => { :checklist => { :subject => '' } }, :headers => credentials('jsmith')
    assert_response :unprocessable_entity
  end

  def test_requires_the_view_permission
    Role.find(1).remove_permission!(:view_expert_checklists)
    get '/issues/1/expert_checklist_items.json', :headers => credentials('jsmith')
    assert_response :forbidden
  end

  def test_issue_api_accepts_nested_items
    put '/issues/1.json',
        :params => { :issue => { :expert_checklist_items_attributes => [{ :subject => 'Via issue API' }] } },
        :headers => credentials('jsmith')
    assert_response :no_content
    assert_include 'Via issue API', @issue.reload.expert_checklist_items.map(&:subject)
  end

  def test_redmineup_compatible_paths_without_redmineup
    skip 'RedmineUP Checklists is installed, its own routes answer' if RedmineExpertChecklists.redmineup_present?

    get '/issues/1/checklists.json', :headers => credentials('jsmith')
    assert_response :success
    assert_equal 2, ActiveSupport::JSON.decode(response.body)['total_count']

    put "/checklists/#{@items[1].id}.json", :params => { :checklist => { :is_done => true } },
                                            :headers => credentials('jsmith')
    assert_response :no_content
    assert @items[1].reload.is_done?

    put '/issues/1.json',
        :params => { :issue => { :checklists_attributes => [{ :subject => 'Old name' }] } },
        :headers => credentials('jsmith')
    assert_include 'Old name', @issue.reload.expert_checklist_items.map(&:subject)
  end
end
