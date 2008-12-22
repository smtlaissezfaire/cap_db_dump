Capistrano::Configuration.instance(:must_exist).load do
  namespace :database do
    # If you give a name for the session table, only the schema for that table will
    # be backed up. If the value is nil, disregard this option
    set :sessions_table,     nil 

    set :dump_root_path, "/tmp"
    set :now, Time.now
    set :formatted_time, now.strftime("%Y-%m-%d-%H:%M:%S")
    set :keep_dumps, 3
    
    class << self
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
        database_yml_in_env["host"]
      end
      
      def database_password
        database_yml_in_env["password"]
      end
      
      def database_yml_in_env
        database_yml[rails_env]
      end
      
      def database_yml
        if @database_yml
          @database_yml
        else
          read_db_yml
          @database_yml = YAML.load(@database_yml)
        end
      end
      
      def tasks_matching_for_db_dump
        { :only => option_for_db_dump }
      end
      
      def option_for_db_dump
        { :db_dump => true }
      end
    end
    
    task :read_db_yml, tasks_matching_for_db_dump do
      run("cat #{shared_path}/config/database.yml") do |_, _, data|
        @database_yml = data
      end
    end

    desc "Remove all but the last 3 production dumps"
    task :cleanup, tasks_matching_for_db_dump do
      cmd = "ls #{dump_root_path}/"

      give_description "Cleaning up files"
      
      run cmd do |channel, stream, data|
        unless stream == :err
          each_database_file_with_index(data) do |file_name, index|
            if index >= keep_dumps
              give_description "Removing old dump #{file_name}"
              run "rm -rf #{file_name}"
            end
          end
        end
      end
    end
    
    def find_server_matching_options
      role_names = roles.map {  |role| role[0] } # an array of role symbol names, like [:app, :db]
      role_names.each { |role_name|
        roles[role_name].servers.each { |server|
          if server.options[:db_dump] == true
            return server
          end
        }
      }
      nil
    end
    
    def server_matching_options
      @server_matching_options ||= find_server_matching_options
    end
    
    def each_database_file_with_index(data)
      all_files = data.split(" ")
      
      if all_files
        if database_files = all_files.select { |f| f =~ /#{database_name}/ }
          database_files.sort.reverse.each_with_index do |file, index|
            yield file, index
          end
        end
      end
    end

    def password_field
      database_password && database_password.any? ? "-p#{database_password}" : ""
    end

    task :create_dump, tasks_matching_for_db_dump do
      ignore_sessions = sessions_table ? "--ignore-table=#{database_name}.sessions" : ""
      
      command = <<-HERE
        mysqldump -u #{database_username} -h #{database_host} #{password_field} -Q  --add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction #{ignore_sessions} #{database_name} > #{dump_path}
      HERE

      give_description "About to dump production DB"

      run command
      session_schema_dump if sessions_table
    end
    
    task :session_schema_dump, tasks_matching_for_db_dump do
      command = <<-HERE
        mysqldump -u #{database_username} -h #{database_host} #{password_field} -Q --add-drop-table --single-transaction --no-data #{database_name} sessions >> #{dump_path}
      HERE

      give_description "Dumping sessions table from db"

      run command
    end

    desc "Create a dump of the production database"
    task :dump, tasks_matching_for_db_dump do
      cleanup
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
end
