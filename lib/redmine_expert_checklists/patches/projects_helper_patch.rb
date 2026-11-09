module RedmineExpertChecklists
  module Patches
    # Adds the "Checklist templates" tab to the project settings, for users who
    # may manage templates there while the module is on.
    #
    # UnboundMethod capture rather than prepend: several plugins installed
    # alongside wrap project_settings_tabs with alias_method.
    module ProjectsHelperPatch
      def self.apply!(base = ProjectsHelper)
        return if base.instance_variable_get(:@expert_checklists_patched)

        original = base.instance_method(:project_settings_tabs)
        base.send(:define_method, :project_settings_tabs) do
          tabs = original.bind(self).call
          if RedmineExpertChecklists.enabled?(@project) &&
             User.current.allowed_to?(:manage_expert_checklist_templates, @project)
            tabs << { :name => 'expert_checklist_templates', :action => :manage_expert_checklist_templates,
                      :partial => 'projects/settings/expert_checklist_templates',
                      :label => :label_expert_checklist_templates }
          end
          tabs
        end

        base.instance_variable_set(:@expert_checklists_patched, true)
      end
    end
  end
end
