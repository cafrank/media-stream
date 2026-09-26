# The server's httpd build (httpd-2.4.6-97.el7.centos, prefork, mod_lua, Lua 5.1) with signed_urls.lua
FROM centos:7
RUN sed -i -e 's/^mirrorlist=/#mirrorlist=/' -e 's|^#\?baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' /etc/yum.repos.d/CentOS-*.repo \
 && yum -y -q install httpd-2.4.6-97.el7.centos httpd-tools-2.4.6-97.el7.centos \
 && yum clean all
# Like the server: /var/www/html has "Options Indexes FollowSymLinks", files are symlinks to other disks
RUN mkdir -p /var/www/html/prev/gen3 /var/www/html/plain /etc/httpd/signed-urls /mnt/disk2 \
 && head -c 5000000 /dev/urandom > /mnt/disk2/video.mp4 \
 && ln -s /mnt/disk2/video.mp4 /var/www/html/prev/gen3/402391.mp4 \
 && ln -s /mnt/disk2/video.mp4 /var/www/html/plain/402391.mp4 \
 && echo hello > /var/www/html/index.html \
 && sed -i 's/^Listen 80$/Listen 8080/' /etc/httpd/conf/httpd.conf \
 && rm -f /etc/httpd/conf.d/welcome.conf
COPY signed_urls.lua /etc/httpd/signed-urls/signed_urls.lua
COPY signed-urls.conf /etc/httpd/conf.d/signed-urls.conf
CMD ["httpd", "-DFOREGROUND"]
