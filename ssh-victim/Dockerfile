FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server \
      rsyslog \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Create the lab user (password: a1)
RUN useradd -m -s /bin/bash victima \
 && echo "victima:a1" | chpasswd

# Basic SSH hardening for a lab (still allows password auth)
RUN sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22

CMD ["/start.sh"]

