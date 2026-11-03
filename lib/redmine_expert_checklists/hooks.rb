module RedmineExpertChecklists
  # View hooks. No Deface: the checklist block and the form editor sit at core's
  # hook points, the assets in <head> (small and inert where no checklist is on
  # the page, like the lightbox plugin).
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(_context = {})
      stylesheet_link_tag('expert_checklists', :plugin => 'redmine_expert_checklists') +
        javascript_include_tag('expert_checklists', :plugin => 'redmine_expert_checklists')
    end

    def view_issues_show_description_bottom(context = {})
      issue = context[:issue]
      return '' unless RedmineExpertChecklists.viewable?(issue)

      context[:hook_caller].send(:render, :partial => 'issues/expert_checklist',
                                          :locals => { :issue => issue })
    end

    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      return '' unless RedmineExpertChecklists.editable?(issue)

      context[:hook_caller].send(:render, :partial => 'issues/expert_checklist_form',
                                          :locals => { :issue => issue, :form => context[:form] })
    end
  end
end
