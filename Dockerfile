FROM alpine:3.12.0

ARG TZ='Europe/Brussels'

ENV TZ ${TZ}

RUN apk update

RUN apk add --no-cache bash fping net-snmp-tools nmap python3 py3-pip py3-virtualenv py3-yaml tzdata procps

# Create the network-discovery folder
RUN mkdir -p /opt/network-discovery
RUN chmod -R 755 /opt/network-discovery

# Add files
ADD . /opt/network-discovery
ADD functions/entrypoint.sh /entrypoint.sh

RUN chmod -R 755 /entrypoint.sh
RUN chmod -R 755 /opt/network-discovery/discover.sh
RUN chmod -R 755 /opt/network-discovery/etc/run_postprocessor.sh

WORKDIR /opt/network-discovery

ENTRYPOINT /entrypoint.sh

