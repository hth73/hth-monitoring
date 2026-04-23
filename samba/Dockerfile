FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
      samba \
      krb5-user \
      winbind \
      smbclient \
      dnsutils \
      iproute2 \
      procps \
      && rm -rf /var/lib/apt/lists/*

# Optional: tools für debugging
RUN apt-get update && apt-get install -y ldap-utils

# Entrypoint Script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/var/lib/samba", "/etc/samba"]

EXPOSE 53 88 135 137/udp 138/udp 139 389 445 464 636

ENTRYPOINT ["/entrypoint.sh"]
