# Headless X11 desktop for testing WolfClip: Xvfb + openbox + compositor.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-gi gir1.2-gtk-4.0 libxtst6 librsvg2-common \
      xvfb openbox xcompmgr feh xdotool xclip x11-utils imagemagick \
      dbus dbus-x11 adwaita-icon-theme fonts-cantarell fonts-inter fonts-dejavu-core \
      gsettings-desktop-schemas \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
