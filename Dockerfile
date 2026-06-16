# The Flutter web build is produced on the CI runner (so Flutter isn't needed in
# the image); this stage just serves the static output with nginx + SPA fallback.
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 80
