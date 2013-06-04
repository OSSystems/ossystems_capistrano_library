Capistrano::Configuration.instance(:must_exist).load do
  VALID_DATABASE_OPTIONS = {"postgresql" => "postgresql.yml.erb",
    "sqlite3" => "sqlite3.yml.erb"}.freeze

  set(:database) { ENV["DATABASE"] || application_config["database"] || database_config[rails_env]["adapter"] }
  set(:database_config) { get_database_config }
  set :database_config_dir, "config/database_config"
  set :database_config_templates_dir, File.join(templates_path, "database")
  set(:database_config_template_filepath) { get_database_config_template_filepath }
  set :database_file_shared_dir, "database_file"
  set(:database_file_path) { database_config[rails_env]["database"] }
  set :setup_database_schema, application_config["setup_database_schema"].nil? ? true : application_config["setup_database_schema"]

  shared_children.push database_config_dir

  namespace :deploy do
    desc "[internal] Creates the PostgreSQL database user that will be used by the application"
    task :add_postgresql_database_user do
      if database == "postgresql"
        [application_user, "root"].each do |database_user|
          command = "#{sudo} -u postgres bash -c \"psql postgres -tAc \\\"SELECT 1 FROM pg_roles WHERE rolname='#{database_user}'\\\" | grep -q 1\""
          status = get_return_status(command)
          if status != 0 # return status != 0 => PostgreSQL user does not exist
            if database_user != "root"
              options = ["--no-createdb",
                         "--no-inherit",
                         "--no-createrole",
                         "--no-superuser",
                         "--no-password"].join(" ")
            else
              options = "--superuser --no-password"
            end

            sudo "createuser #{options} #{database_user}", :as => "postgres"
          else
            puts "PostgreSQL user '#{database_user}' already exists. Ignoring..."
          end
        end
      end
    end

    desc "Load the schema into the database"
    task :schema_load do
      prepare_logs_for_migration do
        sudo_command_user = database == "postgresql" ? "postgres" : nil
        rvmsudo "rake db:schema:load", sudo_command_user
      end
    end

    desc "Run the migrate rake task"
    task :migrate do
      prepare_logs_for_migration do
        sudo_command_user = "-u postgres" if database == "postgresql"
        run "rvm#{sudo} #{sudo_command_user} bash -c 'cd #{current_path} && RAILS_ENV=#{rails_env} bundle exec rake db:migrate'"
      end
    end

    desc "Generate a file containing the application database configuration."
    task :generate_database_config do
      remote_dir = File.join(shared_path, File.basename(database_config_dir))
      database_config_remote_filepath = File.join(remote_dir, "database.yml")
      buffer = parse_template(database_config_template_filepath)
      put buffer, database_config_remote_filepath
      database_remote_filepath = File.join(remote_dir, "database")
      put database, database_remote_filepath
    end

    desc "[internal] Generate a link to the database config file."
    task :link_database_config do
      linked_file = File.join deploy_to, "current/config/database.yml"
      file = File.join current_path, database_config_dir, "database.yml"
      run "rm -f #{linked_file}"
      run "ln -s #{file} #{linked_file}"
    end

    desc "[internal] Generate a link to the database file."
    task :link_database_file do
      database_file = File.join shared_path, database_config_dir, File.basename(database_file_path)
      link = File.join release_path, database_file_path
      run "rm -f #{link}"
      run "mkdir -p #{File.dirname(link)}"
      run "ln -s #{database_file} #{link}"
    end

    desc "[internal] Set the database config file just before starting a new " +
      "deployment"
    task :set_database_config do
      # just by calling this variable the new config filename will be set:
      database
      deploy.add_database_dir_to_shared_if_sqlite
    end

    desc "[internal] Set the database directory if it is an sqlite directory"
    task :add_database_dir_to_shared_if_sqlite do
      if database == "sqlite3"
        shared_children.push database_file_shared_dir
      end
    end
  end

  namespace :db do
    desc "Creates the database"
    task :setup do
      db.create
      deploy.schema_load
      db.seed
    end

    desc "Creates the database"
    task :create do
      command_user = (database == "postgresql" ? "postgres" : nil)
      rvmsudo "rake db:create", command_user
    end

    desc "Seeds the database with initial data"
    task :seed do
      rvmsudo "rake db:seed", application_user
    end

    desc "Set table permissions for the application user"
    task :set_permissions do
      if database == "postgresql"
        # To avoid fighting the string escaping with capistrano I added this
        # small sql script to be generated in runtime from a template, copied to
        # the server and run. After it's completion the generated file is
        # deleted from both the server and the local machine.
        #
        # -- Lucas
        database = database_config[rails_env]["database"]
        buffer = parse_template("set_postgresql_permissions.sql.erb")
        temp_filepath = "/tmp/#{application}_initd_temp_file"
        begin
          put buffer, temp_filepath
          sudo "bash -c 'cd #{current_path} && psql --file=#{temp_filepath} #{database}'", :as => "postgres"
        ensure
          sudo "rm -rf " + temp_filepath
        end
      end
    end

    desc "[internal] Add PostgreSQL to dependencies if is needed"
    task :add_postgresql_to_dependencies_if_needed do
      if database == "postgresql"
        optional_dependencies << "postgresql"
        add_service_dependence("postgresql")
      end
    end

    desc "[internal] Fix SQLite permissions if needed"
    task :fix_sqlite_permissions do
      if database == "sqlite3"
        sudo "chmod -R g+w " + File.join(shared_path, database_file_shared_dir)
      end
    end
  end

  before 'deploy:dependencies', 'db:add_postgresql_to_dependencies_if_needed'
  before 'deploy:update', "deploy:add_database_dir_to_shared_if_sqlite"
  after "deploy:update", "deploy:link_database_config"
  after "deploy:schema_load", "db:set_permissions"
  before "db:create", "db:fix_sqlite_permissions"
  after "deploy:first_code_deployed", "deploy:generate_database_config"
  before 'deploy:cold', "deploy:set_database_config"
  after "deploy:add_user", "deploy:add_postgresql_database_user"

  if setup_database_schema
    after 'after:finalize_update', 'deploy:link_database_file'
    after "deploy:migrate", "db:set_permissions"
    after "deploy:generate_database_config", "deploy:link_database_config"
    after "deploy:first_code_deployed", "db:setup"
  end

  def prepare_logs_for_migration
    log_file_path = File.join(current_path, "log/#{rails_env}.log")
    schema_file_path = File.join(current_path, "db/schema.rb")
    sudo "touch " + log_file_path
    sudo "touch " + schema_file_path
    sudo "chmod o+w " + log_file_path
    sudo "chmod o+w " + schema_file_path
    yield
    sudo "chmod o-w " + schema_file_path
    sudo "chmod o-w " + log_file_path
  end

  def get_database_config
    if ENV["DATABASE"]
      set :database, ENV["DATABASE"]
      raw_database_config_buffer = parse_template(get_database_config_template_filepath)
    else
      raw_database_config_buffer = get_remote_database_config_file
      if raw_database_config_buffer.nil?
        filepath = File.join(Dir.pwd, 'config/database.yml')
        unless File.exists? filepath
          message = <<-END
            Database not specified and remote database file not found.
            Aborting...
          END
          raise Capistrano::CommandError.new(message)
        end
        raw_database_config_buffer = File.read filepath
      end
    end

    return YAML::load( raw_database_config_buffer )
  end

  def get_database_config_template_filepath(database_template_name=nil)
    database_template_name = database if database_template_name.nil?
    config_file = VALID_DATABASE_OPTIONS[database_template_name]
    return File.join("database", config_file)
  end

  def get_remote_database_config_file
    database_remote_filepath = File.join(current_path, "config/database.yml")
    tempfile = Dir::Tmpname.make_tmpname "/tmp/cap_#{application}", nil
    raw_database_config_buffer = nil
    begin
      top.get database_remote_filepath, tempfile
      raw_database_config_buffer = File.read tempfile.strip
    rescue Exception
      # Meh... File doesn't exists. Ignore...
    ensure
      FileUtils.remove_entry_secure tempfile if File.exist? tempfile
    end
    return raw_database_config_buffer
  end
end
