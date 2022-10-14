Capistrano::Configuration.instance(:must_exist).load do
  namespace :database do
    DATABASE_ENGINES = [
      MYSQL = :mysql,
      POSTGRES = :psql,
    ]

    # a list of tables for which only the schema, but no data should be dumped.
    set :schema_only_tables, []
    set :dump_root_path,     "/tmp"
    set :formatted_time,     Time.now.utc.strftime("%Y-%m-%d-%H:%M:%S")
    set :database_engine, :mysql # specify :mysql | :psql

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

      def database_port
        database_yml_in_env["port"]
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
        if dry_run
          raise "Cannot be run in dry_run mode!"
        end

        yaml = capture("cat #{current_path}/config/database.yml")
        YAML.safe_load(yaml, aliases: true)
      end
    end

    def mysql_password_field
      database_password && database_password.length > 0 ? "-p#{database_password}" : ""
    end

    def postgres_port
      database_port ? "-p #{database_port}" : ""
    end

    def pg_password
      database_password && !database_password.empty? ?
        "PGPASSWORD=#{database_password}" :
        ""
    end

    def pg_port
      database_port && !database_port.empty? ? "-p #{database_port}" : ""
    end

    task :create_dump, tasks_matching_for_db_dump do
      if database_engine == MYSQL
        ignored_tables = schema_only_tables.map { |table_name|
          "--ignore-table=#{database_name}.#{table_name}"
        }

        ignored_tables = ignored_tables.join(" ")

        command = "mysqldump -u #{database_username} -h #{database_host} #{mysql_password_field} -Q "
        command << "--add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction "
        command << "#{ignored_tables} #{database_name} > #{dump_path}"
      elsif database_engine == POSTGRES
        ignored_tables = schema_only_tables.map { |table_name|
          "--exclude-table=#{database_name}.#{table_name}"
        }

        ignored_tables = ignored_tables.join(" ")

        command = "#{pg_password} pg_dump -U #{database_username} -h #{database_host} #{postgres_port}"
        command << "#{ignored_tables} #{database_name} > #{dump_path}"
      else
        raise "Unknown database engine. use one of: #{DATABASE_ENGINES.inspect}"
      end

      give_description "About to dump production DB"

      run command
      dump_schema_tables if schema_only_tables.any?
    end

    task :dump_schema_tables, tasks_matching_for_db_dump do
      if schema_only_tables.any?
        table_names = schema_only_tables.join(" ")

        if database_engine == MYSQL
          command = "mysqldump -u #{database_username} -h #{database_host} #{mysql_password_field} "
          command << "-Q --add-drop-table --single-transaction --no-data #{database_name} #{table_names} >> #{dump_path}"
        elsif database_engine == POSTGRES
          raise "not yet supported. PR's welcome! (https://github.com/smtlaissezfaire/cap_db_dump)"
        else
          raise "Unknown database engine. use one of: #{DATABASE_ENGINES.inspect}"
        end

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
      gzip_file = "#{dump_path}.gz"
      download(gzip_file, ".", :via => :scp)

      give_description "Symlinking locally"
      base_name = File.basename(gzip_file)
      `ln -sf #{base_name} current.sql.gz`
    end
  end
end
