resources :issues, :only => [] do
  resources :expert_checklist_items, :only => [:index, :create]
end
resources :expert_checklist_items, :only => [:show, :update, :destroy] do
  member do
    match 'done', :via => [:put, :patch]
  end
end

post 'expert_checklists/notifications/flush', :to => 'expert_checklist_notifications#flush',
                                              :as => 'expert_checklist_notifications_flush'

get 'expert_checklists/legacy_import', :to => 'expert_checklist_imports#show',
                                       :as => 'expert_checklist_legacy_import'
post 'expert_checklists/legacy_import', :to => 'expert_checklist_imports#create'

# RedmineUP Checklists' REST paths, for clients written against it. Drawn only
# without RedmineUP (a file test: routes are drawn before every plugin is
# registered); while it is installed its own routes answer them.
unless File.exist?(File.join(Redmine::Plugin.directory.to_s, 'redmine_checklists', 'init.rb'))
  get 'issues/:issue_id/checklists(.:format)', :to => 'expert_checklist_items#index',
                                               :as => 'expert_checklists_compat_index'
  post 'issues/:issue_id/checklists(.:format)', :to => 'expert_checklist_items#create',
                                                :as => 'expert_checklists_compat_create'
  get 'checklists/:id(.:format)', :to => 'expert_checklist_items#show',
                                  :as => 'expert_checklists_compat_show'
  match 'checklists/:id(.:format)', :to => 'expert_checklist_items#update', :via => [:put, :patch],
                                    :as => 'expert_checklists_compat_update'
  delete 'checklists/:id(.:format)', :to => 'expert_checklist_items#destroy',
                                     :as => 'expert_checklists_compat_destroy'
  match 'checklists/:id/done(.:format)', :to => 'expert_checklist_items#done', :via => [:put, :patch],
                                         :as => 'expert_checklists_compat_done'
end
