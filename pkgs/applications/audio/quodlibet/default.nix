{
  lib,
  fetchFromGitHub,
  tag ? "",

  # build time
  gettext,
  gobject-introspection,
  wrapGAppsHook3,
  writableTmpDirAsHomeHook,

  # runtime
  adwaita-icon-theme,
  gdk-pixbuf,
  glib,
  glib-networking,
  gtk3,
  gtksourceview,
  kakasi,
  keybinder3,
  libappindicator-gtk3,
  libmodplug,
  librsvg,
  libsoup_3,

  # optional features
  withDbusPython ? false,
  withMusicBrainzNgs ? false,
  withPahoMqtt ? false,
  withPypresence ? false,
  withSoco ? false,

  # backends
  withGstPlugins ? withGstreamerBackend,
  withGstreamerBackend ? true,
  gst_all_1,
  withXineBackend ? true,
  xine-lib,

  # tests
  dbus,
  glibcLocales,
  hicolor-icon-theme,
  python3,
  xvfb-run,
}:
python3.pkgs.buildPythonApplication rec {
  pname = "quodlibet${tag}";
  version = "4.7.1";
  pyproject = true;

  outputs = [
    "out"
    "doc"
  ];

  src = fetchFromGitHub {
    owner = "quodlibet";
    repo = "quodlibet";
    tag = "release-${version}";
    hash = "sha256-xr3c1e4tjw2YHuKbvNeUPBIFdHEcpztqXjHVDSSxYlo=";
  };

  # Fix "E   ModuleNotFoundError: No module named 'distutils'" in Python 3.12 or newer
  patches = [ ./fix-gdist-python-3.12-and-newer.patch ];

  build-system = [ python3.pkgs.setuptools ];

  postPatch = ''
    # Fix "FileExistsError: File already exists: /nix/store/<...>-quodlibet-4.7.1/bin/quodlibet"
    substituteInPlace pyproject.toml \
      --replace-fail 'quodlibet = "quodlibet.main:main"' ""
  '';

  nativeBuildInputs = [
    gettext
    gobject-introspection
    wrapGAppsHook3
  ]
  ++ (with python3.pkgs; [
    sphinx-rtd-theme
    sphinxHook
  ]);

  buildInputs = [
    adwaita-icon-theme
    gdk-pixbuf
    glib
    glib-networking
    gtk3
    gtksourceview
    kakasi
    keybinder3
    libappindicator-gtk3
    libmodplug
    libsoup_3
  ]
  ++ lib.optionals (withXineBackend) [ xine-lib ]
  ++ lib.optionals (withGstreamerBackend) (
    with gst_all_1;
    [
      gst-plugins-base
      gstreamer
    ]
    ++ lib.optionals (withGstPlugins) [
      gst-libav
      gst-plugins-bad
      gst-plugins-good
      gst-plugins-ugly
    ]
  );

  dependencies =
    with python3.pkgs;
    [
      feedparser
      gst-python
      mutagen
      pycairo
      pygobject3
    ]
    ++ lib.optionals withDbusPython [ dbus-python ]
    ++ lib.optionals withMusicBrainzNgs [ musicbrainzngs ]
    ++ lib.optionals withPahoMqtt [ paho-mqtt ]
    ++ lib.optionals withPypresence [ pypresence ]
    ++ lib.optionals withSoco [ soco ]
    ++ lib.optionals (pythonAtLeast "3.13") [ standard-telnetlib ];

  nativeCheckInputs = [
    dbus
    gdk-pixbuf
    glibcLocales
    hicolor-icon-theme
    xvfb-run
    writableTmpDirAsHomeHook
  ]
  ++ (with python3.pkgs; [
    polib
    pytest
    pytest-xdist
  ]);

  pytestFlags = [
    # missing translation strings in potfiles
    "--deselect=tests/test_po.py::TPOTFILESIN::test_missing"
    # require networking
    "--deselect=tests/plugin/test_covers.py::test_live_cover_download"
    "--deselect=tests/test_browsers_iradio.py::TInternetRadio::test_click_add_station"
    # upstream does actually not enforce source code linting
    "--ignore=tests/quality"
  ]
  ++ lib.optionals (withXineBackend || !withGstPlugins) [
    "--ignore=tests/plugin/test_replaygain.py"
  ];

  env.LC_ALL = "en_US.UTF-8";

  preCheck = ''
    export GDK_PIXBUF_MODULE_FILE=${librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
    export XDG_DATA_DIRS="$out/share:${gtk3}/share/gsettings-schemas/${gtk3.name}:$XDG_ICON_DIRS:$XDG_DATA_DIRS"
  '';

  checkPhase = ''
    runHook preCheck

    xvfb-run -s '-screen 0 1920x1080x24' \
      dbus-run-session --config-file=${dbus}/share/dbus-1/session.conf \
      pytest $pytestFlags

    runHook postCheck
  '';

  preFixup = lib.optionalString (kakasi != null) ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.getBin kakasi})
  '';

  meta = {
    description = "GTK-based audio player written in Python, using the Mutagen tagging library";
    longDescription = ''
      Quod Libet is a GTK-based audio player written in Python, using
      the Mutagen tagging library. It's designed around the idea that
      you know how to organize your music better than we do. It lets
      you make playlists based on regular expressions (don't worry,
      regular searches work too). It lets you display and edit any
      tags you want in the file. And it lets you do this for all the
      file formats it supports. Quod Libet easily scales to libraries
      of thousands (or even tens of thousands) of songs. It also
      supports most of the features you expect from a modern media
      player, like Unicode support, tag editing, Replay Gain, podcasts
      & internet radio, and all major audio formats.
    '';
    homepage = "https://quodlibet.readthedocs.io/en/latest";
    license = lib.licenses.gpl2Plus;
    maintainers = with lib.maintainers; [
      coroa
      pbogdan
    ];
  };
}
