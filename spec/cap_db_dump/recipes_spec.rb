describe "database recipes" do
  def load_recipes
    configuration = Capistrano::Configuration.new
    Capistrano::Configuration.instance = configuration

    # the recipes define top-level constants, which warn every time they're reloaded
    original_verbose = $VERBOSE
    $VERBOSE = nil
    begin
      load File.expand_path("../../lib/cap_db_dump/recipes.rb", __dir__)
    ensure
      $VERBOSE = original_verbose
    end

    configuration
  end

  def stub_database_yml(settings)
    @database.stub(:capture).
      with("cat /u/apps/my_app/current/config/database.yml").
      and_return({ "production" => settings }.to_yaml)
  end

  before do
    @configuration = load_recipes
    @configuration.set :rails_env, "production"
    @configuration.set :current_path, "/u/apps/my_app/current"
    @configuration.set :formatted_time, "2026-10-03-12:00:00"

    @database = @configuration.namespaces[:database]
    @database.stub(:give_description)

    @dump_path = "/tmp/my_app_production_dump_2026-10-03-12:00:00.sql"
  end

  describe "reading database.yml" do
    it "should read the settings for rails_env from the current release" do
      stub_database_yml("database" => "my_app_production", "username" => "deploy", "port" => 5433)

      @database.database_name.should == "my_app_production"
      @database.database_username.should == "deploy"
      @database.database_port.should == 5433
    end

    it "should default the host to localhost" do
      stub_database_yml("database" => "my_app_production")

      @database.database_host.should == "localhost"
    end

    it "should support YAML aliases" do
      @database.stub(:capture).and_return(<<~YAML)
        default: &default
          username: deploy
        production:
          <<: *default
          database: my_app_production
      YAML

      @database.database_username.should == "deploy"
    end

    it "should only read the file once" do
      @database.should_receive(:capture).once.and_return({ "production" => { "database" => "my_app_production" } }.to_yaml)

      @database.database_name
      @database.database_name
    end

    it "should refuse to run in dry_run mode" do
      @configuration.dry_run = true

      lambda { @database.database_name }.should raise_error("Cannot be run in dry_run mode!")
    end

    it "should refuse to run in dry_run mode with database_config_source :rails" do
      @configuration.set :database_config_source, :rails
      @configuration.dry_run = true
      @database.should_not_receive(:capture)

      lambda { @database.database_name }.should raise_error("Cannot be run in dry_run mode!")
    end
  end

  describe "reading the database config when database.yml contains ERB" do
    before do
      @erb_yaml = <<~YAML
        production:
          adapter: postgresql
          database: my_app_production
          username: <%= Rails.application.credentials.dig(:database, :username) %>
          password: <%= Rails.application.credentials.dig(:database, :password) %>
          host: <%= Rails.application.credentials.dig(:database, :host) %>
      YAML

      @runner_command = "cd /u/apps/my_app/current && RAILS_ENV=production bundle exec rails runner " \
        "\"puts :CAP_DB_DUMP_CONFIG_BEGIN, ActiveRecord::Base.connection_db_config.configuration_hash.to_json, :CAP_DB_DUMP_CONFIG_END\""

      @resolved_config = {
        "adapter" => "postgresql",
        "database" => "my_app_production",
        "username" => "deploy",
        "password" => "s3cret",
        "host" => "db.example.com",
        "port" => 5433,
      }
    end

    def stub_cat(yaml)
      @database.stub(:capture).with("cat /u/apps/my_app/current/config/database.yml").and_return(yaml)
    end

    def stub_runner(output)
      @database.stub(:capture).with(@runner_command, :pty => false).and_return(output)
    end

    def runner_output(config)
      "CAP_DB_DUMP_CONFIG_BEGIN\n#{config.to_json}\nCAP_DB_DUMP_CONFIG_END\n"
    end

    it "should use the plain YAML without running rails when there is no ERB" do
      stub_cat({ "production" => { "database" => "my_app_production", "username" => "deploy" } }.to_yaml)
      @database.should_not_receive(:capture).with(@runner_command, anything)

      @database.read_db_yml.should == {
        "production" => { "database" => "my_app_production", "username" => "deploy" }
      }
    end

    it "should ask rails runner for the resolved config when database.yml has ERB" do
      stub_cat(@erb_yaml)
      stub_runner(runner_output(@resolved_config))

      @database.read_db_yml.should == { "production" => @resolved_config }
      @database.database_username.should == "deploy"
      @database.database_password.should == "s3cret"
      @database.database_host.should == "db.example.com"
      @database.database_port.should == 5433
    end

    it "should ignore noise that rails prints around the config" do
      stub_cat(@erb_yaml)
      stub_runner(
        "W, [2026-10-09T23:00:00] WARN -- : DEPRECATION WARNING: something {is: deprecated}\n" \
        "{not the config}\n" \
        "Booting...\n" +
        runner_output(@resolved_config) +
        "at_exit noise\n"
      )

      @database.read_db_yml.should == { "production" => @resolved_config }
    end

    it "should key the config by rails_env as a string" do
      @configuration.set :rails_env, :production
      stub_cat(@erb_yaml)
      stub_runner(runner_output(@resolved_config))

      @database.read_db_yml.keys.should == ["production"]
    end

    it "should not put single quotes in the runner command, since rvm-shell wraps it in them" do
      @database.rails_runner_database_config_command.should_not include("'")
    end

    it "should raise without echoing the output when the config markers are missing" do
      stub_cat(@erb_yaml)
      stub_runner("password: s3cret\n")

      lambda { @database.read_db_yml }.should raise_error(RuntimeError) { |error|
        error.message.should == "Could not find the database config in the output of rails runner"
      }
    end

    it "should always read database.yml as plain YAML with database_config_source :yaml" do
      @configuration.set :database_config_source, :yaml
      stub_cat(@erb_yaml)
      @database.should_not_receive(:capture).with(@runner_command, anything)

      @database.database_username.should == "<%= Rails.application.credentials.dig(:database, :username) %>"
    end

    it "should always use rails runner with database_config_source :rails" do
      @configuration.set :database_config_source, :rails
      @database.should_not_receive(:capture).with("cat /u/apps/my_app/current/config/database.yml")
      stub_runner(runner_output(@resolved_config))

      @database.database_username.should == "deploy"
    end

    it "should accept database_config_source as a string" do
      @configuration.set :database_config_source, "rails"
      stub_runner(runner_output(@resolved_config))

      @database.database_username.should == "deploy"
    end

    it "should raise on an unknown database_config_source" do
      @configuration.set :database_config_source, :env

      lambda { @database.read_db_yml }.should raise_error(/Unknown database_config_source/)
    end

    it "should pass the resolved settings to pg_dump" do
      @configuration.set :database_engine, :psql
      stub_cat(@erb_yaml)
      stub_runner(runner_output(@resolved_config))

      @database.should_receive(:run).with(
        command_line(
          "IFS= read -r PGPASSWORD && export PGPASSWORD && " \
          "pg_dump -U deploy -h db.example.com -p 5433 -Fc my_app_production > #{@dump_path}"
        ),
        :data => "s3cret\n",
        :eof => true,
        :pty => false
      )

      @database.create_dump
    end

    it "should pass the resolved settings to mysqldump" do
      @configuration.set :database_engine, :mysql
      stub_cat(@erb_yaml)
      stub_runner(runner_output(@resolved_config))

      @database.should_receive(:run).with(
        command_line(
          "mysqldump --defaults-extra-file=/dev/stdin -u deploy -h db.example.com -Q " \
          "--add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction " \
          "my_app_production > #{@dump_path}"
        ),
        :data => "[client]\npassword=\"s3cret\"\n",
        :eof => true,
        :pty => false
      )

      @database.create_dump
    end
  end

  describe "port options" do
    [5433, "5433"].each do |port|
      it "should handle a #{port.class} port" do
        stub_database_yml("database" => "my_app_production", "port" => port)

        @database.postgres_port.should == "-p 5433"
        @database.pg_port.should == "-p 5433"
      end
    end

    [nil, ""].each do |port|
      it "should omit the port when it is #{port.inspect}" do
        stub_database_yml("database" => "my_app_production", "port" => port)

        @database.postgres_port.should == ""
        @database.pg_port.should == ""
      end
    end
  end

  describe "create_dump with mysql" do
    before do
      @configuration.set :database_engine, :mysql
      stub_database_yml(
        "database" => "my_app_production",
        "username" => "deploy",
        "host" => "db.example.com",
        "password" => "s3cret"
      )
    end

    it "should pass the password to mysqldump as an option file on stdin" do
      @database.should_receive(:run).with(
        command_line(
          "mysqldump --defaults-extra-file=/dev/stdin -u deploy -h db.example.com -Q " \
          "--add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction " \
          "my_app_production > #{@dump_path}"
        ),
        :data => "[client]\npassword=\"s3cret\"\n",
        :eof => true,
        :pty => false
      )

      @database.create_dump
    end

    it "should escape backslashes in the password" do
      stub_database_yml("database" => "my_app_production", "password" => "back\\slash\"quote#hash")

      @database.should_receive(:run).with(
        anything,
        hash_including(:data => "[client]\npassword=\"back\\\\slash\"quote#hash\"\n")
      )

      @database.create_dump
    end

    it "should run mysqldump without a password option or stdin when there is no password" do
      stub_database_yml("database" => "my_app_production", "username" => "deploy", "password" => "")

      @database.should_receive(:run).with(
        command_line(
          "mysqldump -u deploy -h localhost -Q " \
          "--add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction " \
          "my_app_production > #{@dump_path}"
        )
      )

      @database.create_dump
    end

    it "should dump only the schema of schema_only_tables" do
      @configuration.set :schema_only_tables, [:sessions, :versions]

      @database.should_receive(:run).with(
        command_line(
          "mysqldump --defaults-extra-file=/dev/stdin -u deploy -h db.example.com -Q " \
          "--add-drop-table -O add-locks=FALSE --lock-tables=FALSE --single-transaction " \
          "--ignore-table=my_app_production.sessions --ignore-table=my_app_production.versions " \
          "my_app_production > #{@dump_path}"
        ),
        anything
      ).ordered

      @database.should_receive(:run).with(
        command_line(
          "mysqldump --defaults-extra-file=/dev/stdin -u deploy -h db.example.com " \
          "-Q --add-drop-table --single-transaction --no-data my_app_production sessions versions >> #{@dump_path}"
        ),
        :data => "[client]\npassword=\"s3cret\"\n",
        :eof => true,
        :pty => false
      ).ordered

      @database.create_dump
    end
  end

  describe "create_dump with postgres" do
    before do
      @configuration.set :database_engine, :psql
      stub_database_yml(
        "database" => "my_app_production",
        "username" => "deploy",
        "host" => "db.example.com",
        "password" => "s3cret"
      )
    end

    it "should have the remote shell read PGPASSWORD from stdin" do
      @database.should_receive(:run).with(
        command_line(
          "IFS= read -r PGPASSWORD && export PGPASSWORD && " \
          "pg_dump -U deploy -h db.example.com -Fc my_app_production > #{@dump_path}"
        ),
        :data => "s3cret\n",
        :eof => true,
        :pty => false
      )

      @database.create_dump
    end

    it "should run pg_dump without reading stdin when there is no password" do
      stub_database_yml("database" => "my_app_production", "username" => "deploy")

      @database.should_receive(:run).with(
        command_line("pg_dump -U deploy -h localhost -Fc my_app_production > #{@dump_path}")
      )

      @database.create_dump
    end

    it "should pass the port" do
      stub_database_yml("database" => "my_app_production", "username" => "deploy", "port" => 5433)

      @database.should_receive(:run).with(
        command_line("pg_dump -U deploy -h localhost -p 5433 -Fc my_app_production > #{@dump_path}")
      )

      @database.create_dump
    end

    it "should use pg_dump_format" do
      @configuration.set :pg_dump_format, :d

      @database.should_receive(:run).with(command_line(/ -Fd /), anything)

      @database.create_dump
    end

    it "should dump plain text when pg_dump_format is nil" do
      @configuration.set :pg_dump_format, nil

      @database.should_receive(:run).with(
        command_line(
          "IFS= read -r PGPASSWORD && export PGPASSWORD && " \
          "pg_dump -U deploy -h db.example.com my_app_production > #{@dump_path}"
        ),
        anything
      )

      @database.create_dump
    end

    it "should not support schema_only_tables yet" do
      @configuration.set :schema_only_tables, [:sessions]
      @database.stub(:run)

      lambda { @database.create_dump }.should raise_error(/not yet supported/)
    end
  end

  describe "create_dump with an unknown database engine" do
    it "should raise" do
      @configuration.set :database_engine, :sqlite
      stub_database_yml("database" => "my_app_production")

      lambda { @database.create_dump }.should raise_error(/Unknown database engine/)
    end
  end

  describe "dump" do
    it "should create the dump and gzip it" do
      stub_database_yml("database" => "my_app_production")

      @database.should_receive(:create_dump).ordered
      @database.should_receive(:run).with("gzip -9 #{@dump_path}").ordered

      @database.dump
    end
  end

  describe "transfer" do
    it "should download the gzipped dump and symlink it to current.sql.gz" do
      stub_database_yml("database" => "my_app_production")

      @database.should_receive(:download).with("#{@dump_path}.gz", ".", :via => :scp)
      @database.should_receive(:`).with("ln -sf my_app_production_dump_2026-10-03-12:00:00.sql.gz current.sql.gz")

      @database.transfer
    end
  end

  describe "dump_and_transfer" do
    it "should dump, then transfer" do
      @database.should_receive(:dump).ordered
      @database.should_receive(:transfer).ordered

      @database.dump_and_transfer
    end
  end
end
