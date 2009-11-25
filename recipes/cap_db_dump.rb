namespace :database do
  # If you give a name for the session table, only the schema for that table will
  # be backed up. If the value is nil, disregard this option
  set :sessions_table,     nil

  set :dump_root_path, "/tmp"
  set :now, Time.now
  set :formatted_time, now.strftime("%Y-%m-%d-%H:%M:%S")
  set :keep_dumps, 3

  module CapDbDumpHelpers
    def dump_path
      "#{dump_root_path}/#{database_name}_dump_#{formatted_time}.sql"
    end

    def give_description(desc_string)
      puts "  ** #{desc_string}"
    end

    def database_name
      database_yml_in_env["database"]
    end

    def database_username
      database_yml_in_env["username"]
    end

    def database_host
      database_yml_in_env["host"] || "localhost"
    end

    def database_password
      database_yml_in_env["password"]
    end

    def database_yml_in_env
      database_yml[rails_env]
    end

    def database_yml
      @database_yml ||= read_db_yml
    end

    def tasks_matching_for_db_dump
      { :only => { :db_dump => true } }
    end
  end

  extend CapDbDumpHelpers

  task :read_db_yml, tasks_matching_for_db_dump do
    @database_yml ||= begin
      yaml = capture("cat #{shared_path}/config/database.yml")
      YAML.load(yaml)
    end
  end

  def password_field
    database_password && database_password.any? ? "-p#{database_password}" : ""
  end

  task :create_dump, tasks_matching_for_db_dump do
    ignore_sessions = sessions_table ? "--ignore-table=#{database_name}.sessions" : ""

    command = "mysqldump -u #{database_username} -h #{database_host} #{password_field} -Q "
    command << "--add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction "
    command << "#{ignore_sessions} #{database_name} > #{dump_path}"

    give_description "About to dump production DB"

    run command
    session_schema_dump if sessions_table
  end

  task :session_schema_dump, tasks_matching_for_db_dump do
    command = "mysqldump -u #{database_username} -h #{database_host} #{password_field} "
    command << "-Q --add-drop-table --single-transaction --no-data #{database_name} sessions >> #{dump_path}"

    give_description "Dumping sessions table from db"

    run command
  end

  desc "Create a dump of the production database"
  task :dump, tasks_matching_for_db_dump do
    create_dump

    cmd = "gzip -9 #{dump_path}"

    give_description "Gzip'ing the file"
    run cmd
  end

  desc "Make a production dump, transfer it to this machine"
  task :dump_and_transfer, tasks_matching_for_db_dump do
    dump
    transfer
  end

  task :transfer, tasks_matching_for_db_dump do
    give_description "Grabbing the dump"
    download("#{dump_path}.gz", ".", :via => :scp)
  end
end
