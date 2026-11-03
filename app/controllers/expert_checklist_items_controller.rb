# Direct checklist changes: ticking on the issue page (session + CSRF, JSON
# without a .json suffix so Redmine keeps the session) and the REST API.
#
# The REST API answers under our own paths and, once RedmineUP Checklists is
# gone, under RedmineUP's (/issues/:id/checklists, /checklists/:id) with the
# same root keys and fields, so existing clients keep working. Every change -
# RedmineUP did not journal API creates and deletes - goes through Recorder:
# history entry, bundled mail.
class ExpertChecklistItemsController < ApplicationController
  helper :expert_checklists

  before_action :find_issue, :only => [:index, :create]
  before_action :find_item, :except => [:index, :create]
  before_action :authorize
  before_action :check_issue_visibility

  accept_api_auth :index, :show, :create, :update, :destroy, :done

  def index
    @items = @issue.expert_checklist_items.to_a
    respond_to do |format|
      format.api
      format.html { redirect_to issue_path(@issue) }
    end
  end

  def show
    respond_to do |format|
      format.api
      format.html { redirect_to issue_path(@issue) }
    end
  end

  def create
    @item = ExpertChecklistItem.new(:issue => @issue)
    @item.safe_attributes = item_params
    saved = false
    RedmineExpertChecklists::Recorder.call(@issue) { saved = @item.save }
    respond_to do |format|
      format.api do
        if saved
          render :action => 'show', :status => :created,
                 :location => expert_checklist_item_url(@item, :format => params[:format])
        else
          render_validation_errors(@item)
        end
      end
    end
  end

  def update
    @item.safe_attributes = item_params
    saved = false
    RedmineExpertChecklists::Recorder.call(@issue) { saved = @item.save }
    respond_to do |format|
      format.api { saved ? render_api_ok : render_validation_errors(@item) }
    end
  end

  def destroy
    RedmineExpertChecklists::Recorder.call(@issue) { @item.destroy }
    respond_to do |format|
      format.api { render_api_ok }
    end
  end

  def done
    if @item.is_section?
      render_error :status => 422
      return
    end

    @item.is_done = RedmineExpertChecklists::LegacyDiff.truthy?(params[:is_done])
    RedmineExpertChecklists::Recorder.call(@issue) { @item.save! }
    respond_to do |format|
      format.json { render :json => done_payload }
      format.api { render_api_ok }
      format.html { redirect_to issue_path(@issue) }
    end
  end

  private

  def find_issue
    @issue = Issue.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_item
    @item = ExpertChecklistItem.find(params[:id])
    @issue = @item.issue
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def check_issue_visibility
    deny_access unless @issue.visible?
  end

  # "checklist" is RedmineUP's root key; ours is accepted as well.
  def item_params
    attrs = params[:checklist] || params[:expert_checklist_item] || {}
    attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs
  end

  # What the page needs to stay consistent after a tick: progress, the done
  # ratio the checklist may have changed, and the new lock_version for the edit
  # form on the same page.
  def done_payload
    @issue.reload
    items = @issue.expert_checklist_items.to_a
    done, total = helpers.expert_checklist_progress(items)
    payload = { :id => @item.id, :is_done => @item.is_done?, :done => done, :total => total,
                :lock_version => @issue.lock_version }
    unless @issue.disabled_core_fields.include?('done_ratio')
      payload[:done_ratio] = @issue.done_ratio
      payload[:done_ratio_html] = helpers.progress_bar(@issue.done_ratio, :legend => "#{@issue.done_ratio}%")
    end
    payload
  end
end
