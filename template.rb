=begin
Template Name: My Rails template using Tailwind
Author: Martin Aarhus Gregersen
Author URI: https://mgregersen.dk
Instructions: $ rails new myapp -d <postgresql, mysql, sqlite3> -m template.rb
=end

def source_paths
  [File.expand_path(File.dirname(__FILE__))]
end

def add_gems
  gem 'administrate'
  gem 'devise', '~> 4.7', '>= 4.7.2'
  gem 'devise_masquerade'
  gem 'friendly_id', '~> 5.3'
  gem 'name_of_person', '~> 1.1', '>= 1.1.1'
  gem 'noticed'
  gem 'sidekiq', '~> 6.1', '>= 6.1.1'
  gem 'sitemap_generator'
end

def add_users
  # Install Devise
  generate "devise:install"

  # Configure Devise
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
              env: 'development'

  route "root to: 'home#index'"

  # Create Devise User
  generate :devise, "User", "first_name", "last_name", "admin:boolean"

  # set admin boolean to false by default
  in_root do
    migration = Dir.glob("db/migrate/*").max_by{ |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  # name_of_person gem
  append_to_file("app/models/user.rb", "\nhas_person_name\n", after: "class User < ApplicationRecord")

  # Add Devise masqueradable to users
  inject_into_file("app/models/user.rb", "masqueradable, :", after: "devise :")
end

def copy_templates
  directory "app", force: true
end

def add_tailwind
  run "yarn add tailwindcss"
  run "yarn add @fullhuman/postcss-purgecss"

  run "mkdir -p app/javascript/stylesheets"

  append_to_file("app/javascript/packs/application.js", 'import "stylesheets/application"')
  inject_into_file("./postcss.config.js",
  "let tailwindcss = require('tailwindcss');\n",  before: "module.exports")
  inject_into_file("./postcss.config.js", "\n    tailwindcss('./app/javascript/stylesheets/tailwind.config.js'),", after: "plugins: [")

  run "mkdir -p app/javascript/stylesheets/components"
end

def copy_postcss_config
  run "rm postcss.config.js"
  copy_file "postcss.config.js"
end

# Remove Application CSS
def remove_app_css
  remove_file "app/assets/stylesheets/application.css"
end

def add_sidekiq
  environment "config.active_job.queue_adapter = :sidekiq"

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<-RUBY
    authenticate :user, lambda { |u| u.admin? } do
      mount Sidekiq::Web => '/sidekiq'
    end
  RUBY
  insert_into_file "config/routes.rb", "#{content}\n\n", after: "Rails.application.routes.draw do\n"
end

def add_announcements
  generate "model Announcement published_at:datetime announcement_type name description:text"
  route "resources :announcements, only: [:index]"
end

def add_administrate
  generate "administrate:install"

  append_to_file "app/assets/config/manifest.js" do
    "//= link administrate/application.css\n//= link administrate/application.js"
  end

  gsub_file "app/dashboards/announcement_dashboard.rb",
    /announcement_type: Field::String/,
    "announcement_type: Field::Select.with_options(collection: Announcement::TYPES)"

  gsub_file "app/dashboards/user_dashboard.rb",
    /email: Field::String/,
    "email: Field::String,\n    password: Field::String.with_options(searchable: false)"

  gsub_file "app/dashboards/user_dashboard.rb",
    /FORM_ATTRIBUTES = \[/,
    "FORM_ATTRIBUTES = [\n    :password,"

  gsub_file "app/controllers/admin/application_controller.rb",
    /# TODO Add authentication logic here\./,
    "redirect_to '/', alert: 'Not authorized.' unless user_signed_in? && current_user.admin?"

  environment do <<-RUBY
    # Expose our application's helpers to Administrate
    config.to_prepare do
      Administrate::ApplicationController.helper #{@app_name.camelize}::Application.helpers
    end
  RUBY
  end
end

def add_foreman
  copy_file "Procfile"
end

def add_friendly_id
  generate "friendly_id"
end

# Main setup
source_paths

add_gems

after_bundle do
  add_users
  remove_app_css
  add_sidekiq
  add_announcements
  add_administrate
  add_foreman
  copy_templates
  add_tailwind
  add_friendly_id
  copy_postcss_config

  # Migrate
  rails_command "db:create"
  rails_command "db:migrate"

  git :init
  git add: "."
  git commit: %Q{ -m "Initial commit" }

  say
  say "App successfully initiated using template! 👍", :green
  say
  say "Switch to your app by running:"
  say "$ cd #{app_name}", :yellow
  say
  say "Then run:"
  say "$ rails server", :green
end
