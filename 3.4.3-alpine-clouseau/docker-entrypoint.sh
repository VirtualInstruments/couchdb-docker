#!/bin/sh
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -e

# first arg is `-something` or `+something`
if [ "${1#-}" != "$1" ] || [ "${1#+}" != "$1" ]; then
    set -- /opt/couchdb/bin/couchdb "$@"
fi

# first arg is the bare word `couchdb`
if [ "$1" = 'couchdb' ]; then
    shift
    set -- /opt/couchdb/bin/couchdb "$@"
fi

if [ "$1" = '/opt/couchdb/bin/couchdb' ]; then
    # Ensure directory and config file exist for runtime changes
    mkdir -p /opt/couchdb/etc/local.d
    touch /opt/couchdb/etc/local.d/docker.ini

    if [ "$(id -u)" = "0" ]; then
        # Fix ownership for /opt/couchdb
        find /opt/couchdb \! \( -user couchdb -group couchdb \) -exec chown -f couchdb:couchdb '{}' +
        find /opt/couchdb/data -type d ! -perm 0755 -exec chmod -f 0755 '{}' +
        find /opt/couchdb/data -type f ! -perm 0644 -exec chmod -f 0644 '{}' +
        find /opt/couchdb/etc -type d ! -perm 0755 -exec chmod -f 0755 '{}' +
        find /opt/couchdb/etc -type f ! -perm 0644 -exec chmod -f 0644 '{}' +
        find -L /opt/couchdb-search \! \( -user couchdb -group 0 \) -exec chown -f couchdb:0 '{}' +
        find -L /opt/couchdb-search -type d ! -perm 0755 -exec chmod -f 0755 '{}' +
        find -L /opt/couchdb-search -type f ! -perm 0644 -exec chmod -f 0644 '{}' +
    fi

    # Erlang cookie setup
    kCOOKIE_REGEX='setcookie ([^ ]+)'
    cookie=''
    cookieFile='/opt/couchdb/.erlang.cookie'
    if [ -e "$cookieFile" ]; then
        cookieFileContents="$(cat "$cookieFile" 2>/dev/null)"
    fi

    # If ERL_FLAGS specifies cookie, use it
    case "$ERL_FLAGS" in
        *-setcookie*)
            cookie=$(echo "$ERL_FLAGS" | sed -n 's/.*-setcookie \([^ ]*\).*/\1/p')
            ;;
        *)
            if [ ! -z "$COUCHDB_ERLANG_COOKIE" ]; then
                if [ -n "$cookieFileContents" ] && [ "$cookieFileContents" != "$COUCHDB_ERLANG_COOKIE" ]; then
                    echo >&2
                    echo >&2 "warning: $cookieFile contents do not match COUCHDB_ERLANG_COOKIE"
                    echo >&2
                fi
                cookie=$COUCHDB_ERLANG_COOKIE
            elif [ -n "$cookieFileContents" ]; then
                cookie=$cookieFileContents
            else
                cookie=$(cat /proc/sys/kernel/random/uuid)
            fi
            ERL_FLAGS="$ERL_FLAGS -setcookie $cookie"
            ;;
    esac

    # Write cookie to Clouseau config if missing
    if ! grep -q '^cookie=' /opt/couchdb-search/etc/clouseau.ini 2>/dev/null; then
        echo "cookie=$cookie" >>/opt/couchdb-search/etc/clouseau.ini
    fi

    # Setup Erlang node name in vm.args
    nodename=${NODENAME:-127.0.0.1}
    if ! echo "$ERL_FLAGS" | grep -q -- '-name' && \
       ! grep -q -- '-name' /opt/couchdb/etc/vm.args 2>/dev/null; then
        echo "-name couchdb@$nodename" >>/opt/couchdb/etc/vm.args
    fi

    # Add admin user and secret if provided via environment and missing in config
    if [ ! -z "$COUCHDB_USER" ] && [ ! -z "$COUCHDB_PASSWORD" ]; then
        if ! grep -q "^\[admins\]" /opt/couchdb/etc/local.d/*.ini 2>/dev/null || \
           ! grep -q "^$COUCHDB_USER =" /opt/couchdb/etc/local.d/*.ini 2>/dev/null; then
            printf "\n[admins]\n%s = %s\n" "$COUCHDB_USER" "$COUCHDB_PASSWORD" >>/opt/couchdb/etc/local.d/docker.ini
        fi
    fi

    if [ ! -z "$COUCHDB_SECRET" ]; then
        if ! grep -q "^\[chttpd_auth\]" /opt/couchdb/etc/local.d/*.ini 2>/dev/null || \
           ! grep -q "^secret =" /opt/couchdb/etc/local.d/*.ini 2>/dev/null; then
            printf "\n[chttpd_auth]\nsecret = %s\n" "$COUCHDB_SECRET" >>/opt/couchdb/etc/local.d/docker.ini
        fi
    fi

    # Write erlang cookie file if COUCHDB_ERLANG_COOKIE provided
    if [ ! -z "$COUCHDB_ERLANG_COOKIE" ]; then
        if [ ! -f "$cookieFile" ] || [ "$(cat "$cookieFile" 2>/dev/null)" != "$COUCHDB_ERLANG_COOKIE" ]; then
            echo "$COUCHDB_ERLANG_COOKIE" > "$cookieFile"
        fi
        chown couchdb:couchdb "$cookieFile"
        chmod 600 "$cookieFile"
    fi

    if [ "$(id -u)" = '0' ]; then
        chown -f couchdb:couchdb /opt/couchdb/etc/local.d/docker.ini || true
    fi

    # Verify presence of admins section with at least one admin user
    # Using POSIX grep alternative to confirm non-comment line under [admins]
    if ! grep -q "^\[admins\]" /opt/couchdb/etc/default.d/*.ini /opt/couchdb/etc/local.d/*.ini 2>/dev/null || ! \
       grep -qv "^\s*;" /opt/couchdb/etc/local.d/docker.ini 2>/dev/null; then
        cat >&2 <<-'EOWARN'
*************************************************************
ERROR: CouchDB 3.0+ will no longer run in "Admin Party"
       mode. You *MUST* specify an admin user and
       password, either via your own .ini file mapped
       into the container at /opt/couchdb/etc/local.ini
       or inside /opt/couchdb/etc/local.d, or with
       "-e COUCHDB_USER=admin -e COUCHDB_PASSWORD=password"
       to set it via "docker run".
*************************************************************
EOWARN
        exit 1
    fi

    echo "Starting CouchDB... ERL_FLAGS=$ERL_FLAGS will be used."
    export HOME=/opt/couchdb
    if [ "$(id -u)" = '0' ]; then
        chpst -u couchdb env ERL_FLAGS="$ERL_FLAGS" "$@" &
    else
        chpst env ERL_FLAGS="$ERL_FLAGS" "$@" &
    fi

    echo "Starting CouchDB Search (Clouseau)..."
    export HOME=/opt/couchdb-search

    # Using 'java' in PATH for Alpine compatibility
    if [ "$(id -u)" = '0' ]; then
        chpst -u couchdb java -server \
            -Xmx2G \
            -Dsun.net.inetaddr.ttl=30 \
            -Dsun.net.inetaddr.negative.ttl=30 \
            -Dlog4j.configuration=file:/opt/couchdb-search/lib/simplelogger.properties \
            -XX:OnOutOfMemoryError="kill -9 %p" \
            -XX:+UseConcMarkSweepGC \
            -XX:+CMSParallelRemarkEnabled \
            -classpath "/opt/couchdb-search/lib/*" \
            com.cloudant.clouseau.Main \
            /opt/couchdb-search/etc/clouseau.ini &
    else
        chpst java -server \
            -Xmx2G \
            -Dsun.net.inetaddr.ttl=30 \
            -Dsun.net.inetaddr.negative.ttl=30 \
            -Dlog4j.configuration=file:/opt/couchdb-search/lib/simplelogger.properties \
            -XX:OnOutOfMemoryError="kill -9 %p" \
            -XX:+UseConcMarkSweepGC \
            -XX:+CMSParallelRemarkEnabled \
            -classpath "/opt/couchdb-search/lib/*" \
            com.cloudant.clouseau.Main \
            /opt/couchdb-search/etc/clouseau.ini &
    fi

    wait
fi

