namespace :database do
  # a list of tables for which only the schema, but no data should be dumped.
  set :schema_only_tables, []
  set :dump_root_path,     "/tmp"
  set :now,                Time.now
  set :formatted_time,     now.strftime("%Y-%m-%d-%H:%M:%S")
  set :keep_dumps,         3

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
    ignored_tables = schema_only_tables.map { |table_name|
      "--ignore-table=#{database_name}.#{table_name}"
    }

    ignored_tables = ignored_tables.join(" ")

    command = "mysqldump -u #{database_username} -h #{database_host} #{password_field} -Q "
    command << "--add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction "
    command << "#{ignored_tables} #{database_name} > #{dump_path}"

    give_description "About to dump production DB"

    run command
    dump_schema_tables if schema_only_tables.any?
  end

  task :dump_schema_tables, tasks_matching_for_db_dump do
    if schema_only_tables.any?
      table_names = schema_only_tables.join(" ")

      command = "mysqldump -u #{database_username} -h #{database_host} #{password_field} "
      command << "-Q --add-drop-table --single-transaction --no-data #{database_name} #{table_names} >> #{dump_path}"

      give_description "Dumping schema for tables: #{schema_only_tables.join(", ")}"
      run command
    end
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
