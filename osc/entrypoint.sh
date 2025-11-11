#!/bin/sh
set -eu

# version_greater A B returns whether A > B
version_greater() {
    [ "$(printf '%s\n' "$@" | sort -t '.' -n -k1,1 -k2,2 -k3,3 -k4,4 | head -n 1)" != "$1" ]
}

# return true if specified directory is empty
directory_empty() {
    [ -z "$(ls -A "$1/")" ]
}

run_as() {
    if [ "$(id -u)" = 0 ]; then
        su -p "$user" -s /bin/sh -c "$1"
    else
        sh -c "$1"
    fi
}

# Execute all executable files in a given directory in alphanumeric order
run_path() {
    local hook_folder_path="/docker-entrypoint-hooks.d/$1"
    local return_code=0
    local found=0

    echo "=> Searching for hook scripts (*.sh) to run, located in the folder \"${hook_folder_path}\""

    if ! [ -d "${hook_folder_path}" ] || directory_empty "${hook_folder_path}"; then
        echo "==> Skipped: the \"$1\" folder is empty (or does not exist)"
        return 0
    fi

    find "${hook_folder_path}" -maxdepth 1 -iname '*.sh' '(' -type f -o -type l ')' -print | sort | (
        while read -r script_file_path; do
            if ! [ -x "${script_file_path}" ]; then
                echo "==> The script \"${script_file_path}\" was skipped, because it lacks the executable flag"
                found=$((found-1))
                continue
            fi

            echo "==> Running the script (cwd: $(pwd)): \"${script_file_path}\""
            found=$((found+1))
            run_as "${script_file_path}" || return_code="$?"

            if [ "${return_code}" -ne "0" ]; then
                echo "==> Failed at executing script \"${script_file_path}\". Exit code: ${return_code}"
                exit 1
            fi

            echo "==> Finished executing the script: \"${script_file_path}\""
        done
        if [ "$found" -lt "1" ]; then
            echo "==> Skipped: the \"$1\" folder does not contain any valid scripts"
        else
            echo "=> Completed executing scripts in the \"$1\" folder"
        fi
    )
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    local varValue=$(env | grep -E "^${var}=" | sed -E -e "s/^${var}=//")
    local fileVarValue=$(env | grep -E "^${fileVar}=" | sed -E -e "s/^${fileVar}=//")
    if [ -n "${varValue}" ] && [ -n "${fileVarValue}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    if [ -n "${varValue}" ]; then
        export "$var"="${varValue}"
    elif [ -n "${fileVarValue}" ]; then
        export "$var"="$(cat "${fileVarValue}")"
    elif [ -n "${def}" ]; then
        export "$var"="$def"
    fi
    unset "$fileVar"
}

# usage: parse_database_url
# Parses DATABASE_URL of format postgres://username:password@host:port/database or mysql://username:password@host:port/database
# and sets appropriate database environment variables
# Falls back to SQLite if DATABASE_URL is not provided
parse_database_url() {
    if [ -n "${DATABASE_URL+x}" ]; then
        # Determine database type from protocol
        case "$DATABASE_URL" in
            postgres://*)
                echo "Parsing DATABASE_URL for PostgreSQL configuration"
                
                # Remove protocol prefix (postgres://)
                url_without_protocol="${DATABASE_URL#postgres://}"
                
                # Extract username:password part (before @)
                user_pass_part="${url_without_protocol%%@*}"
                
                # Extract host:port/database part (after @)
                host_db_part="${url_without_protocol#*@}"
                
                # Extract username (before :)
                username="${user_pass_part%%:*}"
                
                # Extract password (after : in user_pass_part)
                password="${user_pass_part#*:}"
                
                # Extract host:port (before /)
                host_port="${host_db_part%%/*}"
                
                # Extract database (after /)
                database="${host_db_part#*/}"
                
                # Set environment variables only if not already set
                if [ -z "${POSTGRES_USER+x}" ]; then
                    export POSTGRES_USER="$username"
                    echo "Set POSTGRES_USER from DATABASE_URL: $POSTGRES_USER"
                fi
                
                if [ -z "${POSTGRES_PASSWORD+x}" ]; then
                    export POSTGRES_PASSWORD="$password"
                    echo "Set POSTGRES_PASSWORD from DATABASE_URL"
                fi
                
                if [ -z "${POSTGRES_HOST+x}" ]; then
                    export POSTGRES_HOST="$host_port"
                    echo "Set POSTGRES_HOST from DATABASE_URL: $POSTGRES_HOST"
                fi
                
                if [ -z "${POSTGRES_DB+x}" ]; then
                    export POSTGRES_DB="$database"
                    echo "Set POSTGRES_DB from DATABASE_URL: $POSTGRES_DB"
                fi
                ;;
            mysql://*)
                echo "Parsing DATABASE_URL for MySQL configuration"
                
                # Remove protocol prefix (mysql://)
                url_without_protocol="${DATABASE_URL#mysql://}"
                
                # Extract username:password part (before @)
                user_pass_part="${url_without_protocol%%@*}"
                
                # Extract host:port/database part (after @)
                host_db_part="${url_without_protocol#*@}"
                
                # Extract username (before :)
                username="${user_pass_part%%:*}"
                
                # Extract password (after : in user_pass_part)
                password="${user_pass_part#*:}"
                
                # Extract host:port (before /)
                host_port="${host_db_part%%/*}"
                
                # Extract database (after /)
                database="${host_db_part#*/}"
                
                # Set environment variables only if not already set
                if [ -z "${MYSQL_USER+x}" ]; then
                    export MYSQL_USER="$username"
                    echo "Set MYSQL_USER from DATABASE_URL: $MYSQL_USER"
                fi
                
                if [ -z "${MYSQL_PASSWORD+x}" ]; then
                    export MYSQL_PASSWORD="$password"
                    echo "Set MYSQL_PASSWORD from DATABASE_URL"
                fi
                
                if [ -z "${MYSQL_HOST+x}" ]; then
                    export MYSQL_HOST="$host_port"
                    echo "Set MYSQL_HOST from DATABASE_URL: $MYSQL_HOST"
                fi
                
                if [ -z "${MYSQL_DATABASE+x}" ]; then
                    export MYSQL_DATABASE="$database"
                    echo "Set MYSQL_DATABASE from DATABASE_URL: $MYSQL_DATABASE"
                fi
                ;;
            *)
                echo "Warning: Unsupported DATABASE_URL protocol. Expected postgres:// or mysql://"
                echo "Falling back to SQLite"
                if [ -z "${SQLITE_DATABASE+x}" ]; then
                    export SQLITE_DATABASE="nextcloud"
                    echo "Set SQLITE_DATABASE=$SQLITE_DATABASE"
                fi
                ;;
        esac
    else
        # Fallback to SQLite if no DATABASE_URL is provided
        if [ -z "${SQLITE_DATABASE+x}" ] && [ -z "${POSTGRES_DB+x}" ] && [ -z "${MYSQL_DATABASE+x}" ]; then
            echo "No DATABASE_URL provided, falling back to SQLite"
            export SQLITE_DATABASE="nextcloud"
            echo "Set SQLITE_DATABASE=$SQLITE_DATABASE"
        fi
    fi
}

# usage: ensure_data_dir_writable
# Ensures NEXTCLOUD_DATA_DIR exists and is writable by the web server user
ensure_data_dir_writable() {
    if [ -n "${NEXTCLOUD_DATA_DIR+x}" ]; then
        echo "Checking NEXTCLOUD_DATA_DIR: $NEXTCLOUD_DATA_DIR"
        echo "Current user: $(id -u):$(id -g), Web server user: $user:$group"
        
        # Create directory if it doesn't exist
        if [ ! -d "$NEXTCLOUD_DATA_DIR" ]; then
            echo "Creating data directory: $NEXTCLOUD_DATA_DIR"
            mkdir -p "$NEXTCLOUD_DATA_DIR"
            if [ "$(id -u)" = 0 ]; then
                chown "$user:$group" "$NEXTCLOUD_DATA_DIR"
                chmod 755 "$NEXTCLOUD_DATA_DIR"
            fi
        fi
        
        # Set ownership and permissions
        if [ "$(id -u)" = 0 ]; then
            echo "Setting ownership and permissions..."
            chown -R "$user:$group" "$NEXTCLOUD_DATA_DIR"
            chmod 755 "$NEXTCLOUD_DATA_DIR"
        fi
        
        # Show current permissions for debugging
        ls -ld "$NEXTCLOUD_DATA_DIR" || true
        
        # Test writability by creating a test file
        test_file="$NEXTCLOUD_DATA_DIR/.write_test_$$"
        if run_as "touch '$test_file'" 2>/dev/null && [ -f "$test_file" ]; then
            run_as "rm -f '$test_file'" 2>/dev/null || true
            echo "Data directory is writable: $NEXTCLOUD_DATA_DIR"
        else
            echo "ERROR: Cannot write to data directory: $NEXTCLOUD_DATA_DIR"
            echo "Directory permissions:"
            ls -la "$NEXTCLOUD_DATA_DIR/" 2>/dev/null || true
            echo "Parent directory permissions:"
            ls -ld "$(dirname "$NEXTCLOUD_DATA_DIR")" 2>/dev/null || true
            exit 1
        fi
        
        echo "Data directory is ready: $NEXTCLOUD_DATA_DIR"
    fi
}

# usage: start_install_status_server
# Starts a simple HTTP server on port 8080 during installation
start_install_status_server() {
    if [ -f "/install-status.sh" ] && [ "$installed_version" = "0.0.0.0" ]; then
        echo "Starting installation status server on port 8080..."
        chmod +x /install-status.sh
        /install-status.sh 8080 &
        echo $! > /tmp/install_server_main.pid
        echo "Installation status server started (PID: $!)"
    fi
}

# usage: stop_install_status_server  
# Stops the installation status server
stop_install_status_server() {
    # Signal completion to the status server
    touch /tmp/install_complete
    
    # Kill the main server process if it's running
    if [ -f "/tmp/install_server_main.pid" ]; then
        main_pid=$(cat /tmp/install_server_main.pid)
        if kill -0 "$main_pid" 2>/dev/null; then
            echo "Stopping installation status server (PID: $main_pid)"
            kill "$main_pid" 2>/dev/null || true
        fi
        rm -f /tmp/install_server_main.pid
    fi
    
    # Kill PHP server if it's running
    if [ -f "/tmp/php_server.pid" ]; then
        php_pid=$(cat /tmp/php_server.pid)
        if kill -0 "$php_pid" 2>/dev/null; then
            echo "Stopping PHP status server (PID: $php_pid)"
            kill "$php_pid" 2>/dev/null || true
        fi
        rm -f /tmp/php_server.pid
    fi
    
    # Kill any remaining status server processes
    if [ -f "/tmp/install_server.pid" ]; then
        server_pid=$(cat /tmp/install_server.pid)
        if kill -0 "$server_pid" 2>/dev/null; then
            kill "$server_pid" 2>/dev/null || true
        fi
        rm -f /tmp/install_server.pid
    fi
    
    # Cleanup
    rm -f /tmp/install_complete /tmp/install_status /tmp/status_server.php
    echo "Installation status server stopped"
}

# usage: update_install_status "message"
# Updates the installation status message
update_install_status() {
    echo "$1" > /tmp/install_status 2>/dev/null || true
}

# usage: setup_overwrite_config
# Sets OVERWRITEHOST and OVERWRITEPROTOCOL based on OSC_HOSTNAME
setup_overwrite_config() {
    if [ -n "${OSC_HOSTNAME+x}" ]; then
        echo "Setting Nextcloud overwrite configuration for hostname: $OSC_HOSTNAME"
        export OVERWRITEHOST="$OSC_HOSTNAME"
        export OVERWRITEPROTOCOL="https"
        echo "Set OVERWRITEHOST=$OVERWRITEHOST"
        echo "Set OVERWRITEPROTOCOL=$OVERWRITEPROTOCOL"
    fi
}

if expr "$1" : "apache" 1>/dev/null; then
    if [ -n "${APACHE_DISABLE_REWRITE_IP+x}" ]; then
        a2disconf remoteip
    fi
fi

if expr "$1" : "apache" 1>/dev/null || [ "$1" = "php-fpm" ] || [ "${NEXTCLOUD_UPDATE:-0}" -eq 1 ]; then
    uid="$(id -u)"
    gid="$(id -g)"
    if [ "$uid" = '0' ]; then
        case "$1" in
            apache2*)
                user="${APACHE_RUN_USER:-www-data}"
                group="${APACHE_RUN_GROUP:-www-data}"

                # strip off any '#' symbol ('#1000' is valid syntax for Apache)
                user="${user#'#'}"
                group="${group#'#'}"
                ;;
            *) # php-fpm
                user='www-data'
                group='www-data'
                ;;
        esac
    else
        user="$uid"
        group="$gid"
    fi

    # Set up hostname overwrite configuration
    setup_overwrite_config

    # Ensure data directory is writable
    ensure_data_dir_writable

    if [ -n "${REDIS_HOST+x}" ]; then

        echo "Configuring Redis as session handler"
        {
            file_env REDIS_HOST_PASSWORD
            echo 'session.save_handler = redis'
            # check if redis host is an unix socket path
            if [ "$(echo "$REDIS_HOST" | cut -c1-1)" = "/" ]; then
              if [ -n "${REDIS_HOST_PASSWORD+x}" ]; then
                if [ -n "${REDIS_HOST_USER+x}" ]; then
                  echo "session.save_path = \"unix://${REDIS_HOST}?auth[]=${REDIS_HOST_USER}&auth[]=${REDIS_HOST_PASSWORD}\""
                else
                  echo "session.save_path = \"unix://${REDIS_HOST}?auth=${REDIS_HOST_PASSWORD}\""
                fi
              else
                echo "session.save_path = \"unix://${REDIS_HOST}\""
              fi
            # check if redis password has been set
            elif [ -n "${REDIS_HOST_PASSWORD+x}" ]; then
                if [ -n "${REDIS_HOST_USER+x}" ]; then
                    echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_HOST_PORT:=6379}?auth[]=${REDIS_HOST_USER}&auth[]=${REDIS_HOST_PASSWORD}\""
                else
                    echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_HOST_PORT:=6379}?auth=${REDIS_HOST_PASSWORD}\""
                fi
            else
                echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_HOST_PORT:=6379}\""
            fi
            echo "redis.session.locking_enabled = 1"
            echo "redis.session.lock_retries = -1"
            # redis.session.lock_wait_time is specified in microseconds.
            # Wait 10ms before retrying the lock rather than the default 2ms.
            echo "redis.session.lock_wait_time = 10000"
        } > /usr/local/etc/php/conf.d/redis-session.ini
    fi

    # If another process is syncing the html folder, wait for
    # it to be done, then escape initalization.
    (
        if ! flock -n 9; then
            # If we couldn't get it immediately, show a message, then wait for real
            echo "Another process is initializing Nextcloud. Waiting..."
            flock 9
        fi

        installed_version="0.0.0.0"
        if [ -f /var/www/html/version.php ]; then
            # shellcheck disable=SC2016
            installed_version="$(php -r 'require "/var/www/html/version.php"; echo implode(".", $OC_Version);')"
        fi
        # shellcheck disable=SC2016
        image_version="$(php -r 'require "/usr/src/nextcloud/version.php"; echo implode(".", $OC_Version);')"

        if version_greater "$installed_version" "$image_version"; then
            echo "Can't start Nextcloud because the version of the data ($installed_version) is higher than the docker image version ($image_version) and downgrading is not supported. Are you sure you have pulled the newest image version?"
            exit 1
        fi

        if version_greater "$image_version" "$installed_version"; then
            echo "Initializing nextcloud $image_version ... ($installed_version)"
            
            # Start status server for new installations
            if [ "$installed_version" = "0.0.0.0" ]; then
                start_install_status_server
                update_install_status "Preparing Nextcloud installation..."
            fi
            
            if [ "$installed_version" != "0.0.0.0" ]; then
                if [ "${image_version%%.*}" -gt "$((${installed_version%%.*} + 1))" ]; then
                    echo "Can't start Nextcloud because upgrading from $installed_version to $image_version is not supported."
                    echo "It is only possible to upgrade one major version at a time. For example, if you want to upgrade from version 14 to 16, you will have to upgrade from version 14 to 15, then from 15 to 16."
                    exit 1
                fi
                echo "Upgrading nextcloud from $installed_version ..."
                run_as 'php /var/www/html/occ app:list' | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_before
            fi
            if [ "$(id -u)" = 0 ]; then
                rsync_options="-rlDog --chown $user:$group"
            else
                rsync_options="-rlD"
            fi

            rsync $rsync_options --delete --exclude-from=/upgrade.exclude /usr/src/nextcloud/ /var/www/html/
            for dir in config data custom_apps themes; do
                if [ ! -d "/var/www/html/$dir" ] || directory_empty "/var/www/html/$dir"; then
                    rsync $rsync_options --include "/$dir/" --exclude '/*' /usr/src/nextcloud/ /var/www/html/
                fi
            done
            rsync $rsync_options --include '/version.php' --exclude '/*' /usr/src/nextcloud/ /var/www/html/

            # Install
            if [ "$installed_version" = "0.0.0.0" ]; then
                echo "New nextcloud instance"
                update_install_status "Setting up new Nextcloud instance..."

                file_env NEXTCLOUD_ADMIN_PASSWORD
                file_env NEXTCLOUD_ADMIN_USER

                install=false
                if [ -n "${NEXTCLOUD_ADMIN_USER+x}" ] && [ -n "${NEXTCLOUD_ADMIN_PASSWORD+x}" ]; then
                    # shellcheck disable=SC2016
                    install_options='-n --admin-user "$NEXTCLOUD_ADMIN_USER" --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD"'
                    if [ -n "${NEXTCLOUD_DATA_DIR+x}" ]; then
                        # shellcheck disable=SC2016
                        install_options=$install_options' --data-dir "$NEXTCLOUD_DATA_DIR"'
                    fi

                    # Parse DATABASE_URL if provided
                    parse_database_url
                    
                    file_env MYSQL_DATABASE
                    file_env MYSQL_PASSWORD
                    file_env MYSQL_USER
                    file_env POSTGRES_DB
                    file_env POSTGRES_PASSWORD
                    file_env POSTGRES_USER

                    if [ -n "${SQLITE_DATABASE+x}" ]; then
                        echo "Installing with SQLite database"
                        # shellcheck disable=SC2016
                        install_options=$install_options' --database-name "$SQLITE_DATABASE"'
                        install=true
                    elif [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ -n "${MYSQL_HOST+x}" ]; then
                        echo "Installing with MySQL database"
                        # shellcheck disable=SC2016
                        install_options=$install_options' --database mysql --database-name "$MYSQL_DATABASE" --database-user "$MYSQL_USER" --database-pass "$MYSQL_PASSWORD" --database-host "$MYSQL_HOST"'
                        install=true
                    elif [ -n "${POSTGRES_DB+x}" ] && [ -n "${POSTGRES_USER+x}" ] && [ -n "${POSTGRES_PASSWORD+x}" ] && [ -n "${POSTGRES_HOST+x}" ]; then
                        echo "Installing with PostgreSQL database"
                        # shellcheck disable=SC2016
                        install_options=$install_options' --database pgsql --database-name "$POSTGRES_DB" --database-user "$POSTGRES_USER" --database-pass "$POSTGRES_PASSWORD" --database-host "$POSTGRES_HOST"'
                        install=true
                    fi

                    if [ "$install" = true ]; then
                        run_path pre-installation

                        # Ensure data directory is ready before installation
                        update_install_status "Configuring data directory..."
                        ensure_data_dir_writable

                        echo "Starting nextcloud installation"
                        update_install_status "Installing Nextcloud (this may take several minutes)..."
                        max_retries=10
                        try=0
                        until  [ "$try" -gt "$max_retries" ] || run_as "php /var/www/html/occ maintenance:install $install_options" 
                        do
                            echo "Retrying install..."
                            update_install_status "Installation attempt $((try+1)) of $((max_retries+1))..."
                            try=$((try+1))
                            sleep 10s
                        done
                        if [ "$try" -gt "$max_retries" ]; then
                            echo "Installing of nextcloud failed!"
                            exit 1
                        fi
                        if [ -n "${NEXTCLOUD_TRUSTED_DOMAINS+x}" ]; then
                            echo "Setting trusted domains…"
                            update_install_status "Configuring trusted domains..."
			    set -f # turn off glob
                            NC_TRUSTED_DOMAIN_IDX=1
                            for DOMAIN in ${NEXTCLOUD_TRUSTED_DOMAINS}; do
                                DOMAIN=$(echo "${DOMAIN}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
                                run_as "php /var/www/html/occ config:system:set trusted_domains $NC_TRUSTED_DOMAIN_IDX --value=\"${DOMAIN}\""
                                NC_TRUSTED_DOMAIN_IDX=$((NC_TRUSTED_DOMAIN_IDX+1))
                            done
			    set +f # turn glob back on
                        fi

                        update_install_status "Finalizing installation..."
                        run_path post-installation
		    fi
                fi
		# not enough specified to do a fully automated installation 
                if [ "$install" = false ]; then 
                    echo "Next step: Access your instance to finish the web-based installation!"
                    echo "Hint: You can specify NEXTCLOUD_ADMIN_USER and NEXTCLOUD_ADMIN_PASSWORD and the database variables _prior to first launch_ to fully automate initial installation."
                fi
            # Upgrade
            else
                run_path pre-upgrade

                run_as 'php /var/www/html/occ upgrade'

                run_as 'php /var/www/html/occ app:list' | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_after
                echo "The following apps have been disabled:"
                diff /tmp/list_before /tmp/list_after | grep '<' | cut -d- -f2 | cut -d: -f1
                rm -f /tmp/list_before /tmp/list_after

                run_path post-upgrade
            fi

            echo "Initializing finished"
            
            # Stop status server after installation
            if [ "$installed_version" = "0.0.0.0" ]; then
                update_install_status "Installation completed! Starting Nextcloud..."
                sleep 2  # Give users a moment to see the completion message
                stop_install_status_server
            fi
        fi

        # Update htaccess after init if requested
        if [ -n "${NEXTCLOUD_INIT_HTACCESS+x}" ] && [ "$installed_version" != "0.0.0.0" ]; then
            run_as 'php /var/www/html/occ maintenance:update:htaccess'
        fi
    ) 9> /var/www/html/nextcloud-init-sync.lock

    # warn if config files on persistent storage differ from the latest version of this image
    for cfgPath in /usr/src/nextcloud/config/*.php; do
        cfgFile=$(basename "$cfgPath")

        if [ "$cfgFile" != "config.sample.php" ] && [ "$cfgFile" != "autoconfig.php" ]; then
            if ! cmp -s "/usr/src/nextcloud/config/$cfgFile" "/var/www/html/config/$cfgFile"; then
                echo "Warning: /var/www/html/config/$cfgFile differs from the latest version of this image at /usr/src/nextcloud/config/$cfgFile"
            fi
        fi
    done

    run_path before-starting
fi

exec "$@"