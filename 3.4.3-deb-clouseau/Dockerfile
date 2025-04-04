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

FROM debian:bookworm-slim

ARG CLOUSEAU_VERSION=2.25.0
ARG SLF4J_SIMPLE_BINDING_VERSION=2.0.7
ARG SLF4J_API_BINDING_VERSION=2.0.7

LABEL maintainer="CouchDB Developers dev@couchdb.apache.org"

# Add CouchDB user account to make sure the IDs are assigned consistently
RUN groupadd -g 5984 -r couchdb && useradd -u 5984 -d /opt/couchdb -g couchdb couchdb \
    && echo "couchdb ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers

# be sure GPG and apt-transport-https are available and functional
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        dirmngr \
        gnupg \
     ; \
    rm -rf /var/lib/apt/lists/*

# grab tini for signal handling and zombie reaping
# see https://github.com/apache/couchdb-docker/pull/28#discussion_r141112407
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends tini; \
    rm -rf /var/lib/apt/lists/*; \
    tini --version

# Fetch and extract Clouseau (Debian Bookworm version)
RUN set -xe; \
    apt-get update -y && \
    apt-get install -y --no-install-recommends unzip wget maven && \
    mkdir -p /opt/couchdb-search/lib && \
    wget https://github.com/cloudant-labs/clouseau/releases/download/${CLOUSEAU_VERSION}/clouseau-${CLOUSEAU_VERSION}-dist.zip && \
    unzip -j clouseau-${CLOUSEAU_VERSION}-dist.zip -d /opt/couchdb-search/lib/ && \
    rm -f /opt/couchdb-search/lib/slf4j-api-1.7.2.jar && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mvn dependency:get -Dartifact=org.slf4j:slf4j-simple:${SLF4J_SIMPLE_BINDING_VERSION} -Dartifact=org.slf4j:slf4j-api:${SLF4J_API_BINDING_VERSION} && \
    mvn dependency:copy -Dartifact=org.slf4j:slf4j-simple:${SLF4J_SIMPLE_BINDING_VERSION}:jar -DoutputDirectory=/opt/couchdb-search/lib && \
    mvn dependency:copy -Dartifact=org.slf4j:slf4j-api:${SLF4J_API_BINDING_VERSION}:jar -DoutputDirectory=/opt/couchdb-search/lib

RUN wget http://www.mirbsd.org/~tg/Debs/sources.txt/wtf-bookworm.sources; \
    mkdir -p /etc/apt/sources.list.d; \
    mv wtf-bookworm.sources /etc/apt/sources.list.d/; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends openjdk-8-jdk-headless apt-transport-https ca-certificates runit; \
    cp /etc/runit/2 /sbin/runsvdir-start;

# http://docs.couchdb.org/en/latest/install/unix.html#installing-the-apache-couchdb-packages
ENV GPG_COUCH_KEY \
# gpg: rsa8192 205-01-19 The Apache Software Foundation (Package repository signing key) <root@apache.org>
    390EF70BB1EA12B2773962950EE62FB37A00258D
RUN set -eux; \
    apt-get update; \
    apt-get install -y curl; \
    export GNUPGHOME="$(mktemp -d)"; \
    curl -fL -o keys.asc https://couchdb.apache.org/repo/keys.asc; \
    gpg --batch --import keys.asc; \
    gpg --batch --export "${GPG_COUCH_KEY}" > /usr/share/keyrings/couchdb-archive-keyring.gpg; \
    command -v gpgconf && gpgconf --kill all || :; \
    rm -rf "$GNUPGHOME"; \
    apt-key list; \
    apt purge -y --autoremove curl; \
    rm -rf /var/lib/apt/lists/*

ENV COUCHDB_VERSION 3.4.3

RUN . /etc/os-release; \
    echo "deb [signed-by=/usr/share/keyrings/couchdb-archive-keyring.gpg] https://apache.jfrog.io/artifactory/couchdb-deb/ ${VERSION_CODENAME} main" | \
        tee /etc/apt/sources.list.d/couchdb.list >/dev/null

# https://github.com/apache/couchdb-pkg/blob/master/debian/README.Debian
RUN set -eux; \
    apt-get update; \
    \
    echo "couchdb couchdb/mode select none" | debconf-set-selections; \
    # we DO want recommends this time
    DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades --allow-remove-essential --allow-change-held-packages \
            couchdb="$COUCHDB_VERSION"~bookworm \
    ; \
    # Undo symlinks to /var/log and /var/lib
    rmdir /var/lib/couchdb /var/log/couchdb; \
    rm /opt/couchdb/data /opt/couchdb/var/log; \
    mkdir -p /opt/couchdb/data /opt/couchdb/var/log; \
    chown couchdb:couchdb /opt/couchdb/data /opt/couchdb/var/log; \
    chmod 777 /opt/couchdb/data /opt/couchdb/var/log; \
    # Remove file that sets logging to a file
    rm /opt/couchdb/etc/default.d/10-filelog.ini; \
    # Check we own everything in /opt/couchdb. Matches the command in dockerfile_entrypoint.sh
    find /opt/couchdb \! \( -user couchdb -group couchdb \) -exec chown -f couchdb:couchdb '{}' +; \
    # Setup directories and permissions for config. Technically these could be 555 and 444 respectively
    # but we keep them as 755 and 644 for consistency with CouchDB defaults and the dockerfile_entrypoint.sh.
    find /opt/couchdb/etc -type d ! -perm 0755 -exec chmod -f 0755 '{}' +; \
    find /opt/couchdb/etc -type f ! -perm 0644 -exec chmod -f 0644 '{}' +; \
    # only local.d needs to be writable for the docker_entrypoint.sh
    chmod -f 0777 /opt/couchdb/etc/local.d; \
    # apt clean-up
    rm -rf /var/lib/apt/lists/*;

# Copy Clouseau jar and set directory permissions
# @TODO: Should we push local.ini from the config-store repo?
COPY --chown=couchdb:0 resources/clouseau/clouseau.ini /opt/couchdb-search/etc/
COPY --chown=couchdb:0 resources/clouseau/simplelogger.properties /opt/couchdb-search/lib/

RUN install -d -m 0755 -o couchdb -g 0 -p /opt/couchdb-search/etc /opt/couchdb-search/lib /opt/couchdb/data/search_indexes && \
    find -L /opt/couchdb-search \! \( -user couchdb -group 0 \) -exec chown -f couchdb:0 '{}' +; \
    find -L /opt/couchdb-search -type d ! -perm 0755 -exec chmod -f 0755 '{}' +; \
    find -L /opt/couchdb-search -type f ! -perm 0664 -exec chmod -f 0664 '{}' +;

RUN install -d -m 0775 -o couchdb -g 0 -p /opt/couchdb/etc /opt/couchdb/data /opt/couchdb/bin && \
    find -L /opt/couchdb \! \( -user couchdb -group 0 \) -exec chown -f couchdb:0 '{}' +; \
    find -L /opt/couchdb -type d ! -perm 0775 -exec chmod -f 0775 '{}' +; \
    find -L /opt/couchdb -type f ! -perm 0775 -exec chmod -f 0775 '{}' +;

RUN install -d -m 0775 -o couchdb -g 0 -p /run/runit /etc/service && \
    find -L /run/runit -type d ! -perm 0775 -exec chmod -f 0775 '{}' +; \
    find -L /run/runit -type f ! -perm 0775 -exec chmod -f 0775 '{}' +; \
    find -L /etc/service -type d ! -perm 0775 -exec chmod -f 0775 '{}' +; \
    find -L /etc/service -type f ! -perm 0775 -exec chmod -f 0775 '{}' +;

# Add the License
COPY licenses /licenses

# Add configuration
COPY --chown=couchdb:0 resources/10-docker-default.ini /opt/couchdb/etc/default.d/
COPY --chown=couchdb:0 resources/vm.args /opt/couchdb/etc/
COPY --chown=couchdb:0 resources/run /etc/service/couchdb/
COPY --chown=couchdb:0 resources/run_clouseau /etc/service/couchdb-search/run

# @TODO: Should we push local.ini from the config-store repo?
COPY --chown=couchdb:0 local.ini /opt/couchdb/etc/local.d/

COPY --chown=couchdb:0 docker-entrypoint.sh /usr/local/bin
RUN ln -s usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh # backwards compat

USER couchdb:root

ENTRYPOINT ["tini", "-s", "--", "/docker-entrypoint.sh"]

VOLUME /opt/couchdb/data

# 5984: Main CouchDB endpoint
# 4369: Erlang portmap daemon (epmd)
# 9100: CouchDB cluster communication port
EXPOSE 5984 4369 9100
CMD ["/opt/couchdb/bin/couchdb"]

