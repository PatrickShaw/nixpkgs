{
  lib,
  stdenv,
  fetchurl,
  replaceVars,
  pkg-config,
  libxslt,
  ninja,
  gnome,
  gtk3,
  gtk4,
  glib,
  gettext,
  libxml2,
  xkeyboard_config,
  libxkbcommon,
  isocodes,
  meson,
  wayland,
  libseccomp,
  systemd,
  udev,
  bubblewrap,
  gobject-introspection,
  gtk-doc,
  docbook-xsl-nons,
  gsettings-desktop-schemas,
  withSystemd ? lib.meta.availableOn stdenv.hostPlatform systemd,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gnome-desktop";
  version = "44.3";

  outputs = [
    "out"
    "dev"
    "devdoc"
  ];

  src = fetchurl {
    url = "mirror://gnome/sources/gnome-desktop/${lib.versions.major finalAttrs.version}/gnome-desktop-${finalAttrs.version}.tar.xz";
    sha256 = "sha256-QO+pqo1Q7/7ZIno9cGceMuncNeIPMxyrO1YpdZePT40=";
  };

  patches = lib.optionals stdenv.hostPlatform.isLinux [
    (replaceVars ./bubblewrap-paths.patch {
      bubblewrap_bin = "${bubblewrap}/bin/bwrap";
      inherit (builtins) storeDir;
    })
  ];

  nativeBuildInputs = [
    pkg-config
    meson
    ninja
    gettext
    libxslt
    libxml2
    gobject-introspection
    gtk-doc
    docbook-xsl-nons
    glib
  ];

  buildInputs = [
    xkeyboard_config
    libxkbcommon # for xkbregistry
    isocodes
    gtk3
    gtk4
    glib
  ]
  ++ lib.optionals withSystemd [
    systemd
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    bubblewrap
    wayland
    libseccomp
    udev
  ];

  propagatedBuildInputs = [
    gsettings-desktop-schemas
  ];

  mesonFlags = [
    "-Dgtk_doc=true"
    "-Ddesktop_docs=false"
    (lib.mesonEnable "systemd" withSystemd)
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isLinux) [
    "-Dudev=disabled"
  ];

  separateDebugInfo = stdenv.hostPlatform.isLinux;

  passthru = {
    updateScript = gnome.updateScript {
      packageName = "gnome-desktop";
    };
  };

  meta = with lib; {
    description = "Library with common API for various GNOME modules";
    homepage = "https://gitlab.gnome.org/GNOME/gnome-desktop";
    license = with licenses; [
      gpl2Plus
      lgpl2Plus
    ];
    platforms = platforms.unix;
    teams = [ teams.gnome ];
  };
})
