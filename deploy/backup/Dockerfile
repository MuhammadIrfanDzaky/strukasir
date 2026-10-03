FROM postgres:17-alpine
RUN apk add --no-cache rclone tzdata
COPY backup.sh restore.sh /usr/local/bin/
COPY crontab /etc/crontabs/root
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh
CMD ["crond", "-f", "-l", "8"]
