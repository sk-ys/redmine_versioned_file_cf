RedmineApp::Application.routes.draw do
  resources :versioned_files, only: [] do
    collection do
      get :history
      get :compare
    end
    member do
      get :diff
    end
  end
end