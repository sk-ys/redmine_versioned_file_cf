RedmineApp::Application.routes.draw do
  post 'custom_fields/:id/convert_to_versioned_file', to: 'versioned_file_cf/custom_field_conversions#convert_to_versioned_file', as: :convert_custom_field_to_versioned_file
  post 'custom_fields/:id/convert_to_file', to: 'versioned_file_cf/custom_field_conversions#convert_to_file', as: :convert_custom_field_to_file

  resources :versioned_files, only: [:destroy] do
    collection do
      get :history
      get :compare
      post :update_description
    end
    member do
      get :diff
      post :restore
    end
  end
end