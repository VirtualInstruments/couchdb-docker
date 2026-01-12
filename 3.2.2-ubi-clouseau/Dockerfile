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

ARG CLOUSEAU_VERSION=2.21.0

FROM registry.access.redhat.com/ubi8/ubi-minimal as builder

ARG CLOUSEAU_VERSION
ARG SLF4J_SIMPLE_BINDING_VERSION=1.7.36

WORKDIR /usr/src

# Fetch and extract clouseau
RUN set -xe; \
    microdnf update -y && rm -rf /var/cache/yum && \
    microdnf install -y unzip wget maven && \
    wget https://github.com/cloudant-labs/clouseau/releases/download/${CLOUSEAU_VERSION}/clouseau-${CLOUSEAU_VERSION}-dist.zip && \
    unzip -j clouseau-${CLOUSEAU_VERSION}-dist.zip -d clouseau && \
    microdnf clean all; \
    rm -rf /var/cache/yum

# Fetch and extract slf4j simplelogger binding (log to console)
RUN mvn dependency:get -Dartifact=org.slf4j:slf4j-simple:${SLF4J_SIMPLE_BINDING_VERSION} && \
    mvn dependency:copy -Dartifact=org.slf4j:slf4j-simple:${SLF4J_SIMPLE_BINDING_VERSION}:jar -DoutputDirectory=clouseau

FROM registry.access.redhat.com/ubi8/ubi-minimal

# Install necessary tools for building OpenSSL
RUN microdnf update -y && \
    microdnf install -y wget gcc make tar gzip perl

#Script to install openssl
WORKDIR /usr/src

RUN wget https://www.openssl.org/source/openssl-1.1.1w.tar.gz  && \
    tar -xvzf openssl-1.1.1w.tar.gz && \
    cd openssl-1.1.1w && \
    ./config --prefix=/opt/openssl --openssldir=/usr/local/ssl && \
    make && \
    make install && \
    cd .. && \
    rm -rf openssl-1.1.1w.tar.gz openssl-1.1.1w

#Script to install zlib

RUN wget https://zlib.net/zlib-1.3.1.tar.gz && \
    tar -xvzf zlib-1.3.1.tar.gz && \
    cd zlib-1.3.1 && \
    ./configure --prefix=/opt/zlib && \
    make && \
    make install && \
    cd .. && \
    rm -rf zlib-1.3.1.tar.gz zlib-1.3.1

#Script to install curl

RUN wget https://curl.se/download/curl-8.12.1.tar.gz && \
    tar -xzvf curl-8.12.1.tar.gz && \
    cd curl-8.12.1 && \
    ./configure --prefix /opt/curl --with-openssl=/opt/openssl --with-zlib=/opt/zlib --without-libpsl && \
    make && \
    make install && \
    cd .. && \
    rm -rf curl-8.12.1.tar.gz curl-8.12.1

# Overwrite default curl, openssl with latest-built curl, openssl
RUN ln -sf /opt/curl/bin/curl /usr/bin/curl && \
    ln -sf /opt/openssl/bin/openssl /usr/bin/openssl

# Remove specific old libssl library
RUN rm -f /usr/lib64/libssl.so.1.1.1k

# Link /usr/lib64/libssl.so.1.1 to /opt/openssl/lib/libssl.so.1.1
RUN ln -sf /opt/openssl/lib/libssl.so.1.1 /usr/lib64/libssl.so.1.1

ARG RELEASE
ARG BUILD_DATE
ARG CLOUSEAU_VERSION

LABEL maintainer="CouchDB Developers dev@couchdb.apache.org" \
      name="Apache CouchDB" \
      version="3.2.2" \
      summary="Apache CouchDB based on Red Hat UBI" \
      description="Red Hat OpenShift-compatible container that runs Apache CouchDB" \
      release=${RELEASE}  \
      usage="https://github.com/apache/couchdb-docker" \
      build-date=${BUILD_DATE} \
      io.k8s.display-name="Apache CouchDB" \
      io.k8s.description="Red Hat OpenShift-compatible container that runs Apache CouchDB" \
      io.openshift.tags="database couchdb apache rhel8" \
      io.openshift.expose-services="5984/http,4369/epmd,9100/erlang" \
      io.openshift.min-memory="1Gi" \
      io.openshift.min-cpu="1"

COPY imeyer_runit.repo /etc/yum.repos.d/imeyer_runit.repo
COPY couchdb.repo /etc/yum.repos.d/couchdb.repo

ENV COUCHDB_VERSION=3.2.2 \
    CLOUSEAU_VERSION=${CLOUSEAU_VERSION} \
    JAVA_MAJOR_VERSION=8 \
    JAVA_HOME=/usr/lib/jvm/jre-1.8.0 \
    CLASSPATH=${APP_ROOT}/lib/*

# Add CouchDB user account to make sure the IDs are assigned consistently
# CouchDB user added to root group for OpenShift support
RUN set -ex; \
# be sure GPG and apt-transport-https are available and functional
    microdnf update -y && rm -rf /var/cache/yum; \
    microdnf install -y \
            java-1.8.0-openjdk-headless \
            ca-certificates \
            gnupg \
            findutils \
            shadow-utils; \
# Add CouchDB User and Group (group required by rpm)
    useradd -u 5984 -d /opt/couchdb -g root couchdb; \
    groupadd -g 5984 couchdb; \
# Install runit
    microdnf update --disableplugin=subscription-manager -y && rm -rf /var/cache/yum; \
    microdnf install --enablerepo=imeyer_runit -y runit; \
# Clean up
    microdnf clean all; \
    rm -rf /var/cache/yum

# Install CouchDB
RUN set -xe; \
    microdnf update --disableplugin=subscription-manager -y && rm -rf /var/cache/yum; \
    microdnf install --enablerepo=couchdb -y couchdb-${COUCHDB_VERSION}; \
    microdnf clean all; \
    rm -rf /var/cache/yum; \
# remove defaults that force writing logs to file
    rm /opt/couchdb/etc/default.d/10-filelog.ini; \
# Check we own everything in /opt/couchdb. Matches the command in dockerfile_entrypoint.sh
    find /opt/couchdb \! \( -user couchdb -group 0 \) -exec chown -f couchdb:0 '{}' +; \
# Setup directories and permissions for config. Technically these could be 555 and 444 respectively
# but we keep them as 775 and 664 for consistency with the dockerfile_entrypoint.
    find /opt/couchdb/etc -type d ! -perm 0755 -exec chmod -f 0755 '{}' +; \
    find /opt/couchdb/etc -type f ! -perm 0644 -exec chmod -f 0644 '{}' +; \
# Setup directories and permissions for data.
    chmod 777 /opt/couchdb/data
ENV PATH=/opt/curl/bin/:/opt/openssl/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
LD_LIBRARY_PATH=/opt/openssl/lib:/opt/zlib/lib/

# Copy Clouseau jar and set directory permissions
COPY resources/clouseau/clouseau.ini /opt/couchdb-search/etc/
COPY resources/clouseau/simplelogger.properties /opt/couchdb-search/lib/
COPY --from=builder /usr/src/clouseau/*.jar /opt/couchdb-search/lib/

RUN install -d -m 0755 -o couchdb -g 0 -p /opt/couchdb-search/etc /opt/couchdb-search/lib /opt/couchdb/data/search_indexes && \
    find -L /opt/couchdb-search \! \( -user couchdb -group 0 \) -exec chown -f couchdb:0 '{}' +; \
	find -L /opt/couchdb-search -type d ! -perm 0755 -exec chmod -f 0755 '{}' +; \
    find -L /opt/couchdb-search -type f ! -perm 0644 -exec chmod -f 0644 '{}' +;

# Add the License
COPY licenses /licenses

# Add configuration
COPY --chown=couchdb:0 resources/10-docker-default.ini /opt/couchdb/etc/default.d/
COPY --chown=couchdb:0 resources/vm.args /opt/couchdb/etc/
COPY --chown=couchdb:0 resources/docker-entrypoint.sh /usr/local/bin
COPY --chown=couchdb:0 resources/run /etc/service/couchdb/
COPY --chown=couchdb:0 resources/run_clouseau /etc/service/couchdb-search/run

# set permissions on runit scripts
RUN chmod -R 777 /etc/service/couchdb; \
    chmod -R 777 /etc/service/couchdb-search; \
    chmod 777 /usr/local/bin/docker-entrypoint.sh; \
# symlink to root folder
    ln -s usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh
ENV LD_LIBRARY_PATH=/usr/lib:/usr/lib64/
RUN rpm -qa | grep "curl"

ENTRYPOINT ["/docker-entrypoint.sh"]
VOLUME /opt/couchdb/data

# 5988: Main CouchDB endpoint
# 4369: Erlang portmap daemon (epmd)
# 9100: CouchDB cluster communication port
EXPOSE 5988 4369
CMD ["/opt/couchdb/bin/couchdb"]
