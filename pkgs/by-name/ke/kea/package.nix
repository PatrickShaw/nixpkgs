{
  stdenv,
  lib,
  fetchurl,

  # build time
  meson,
  cmake,
  ninja,
  pkg-config,
  python3Packages,

  # runtime
  withMysql ? stdenv.buildPlatform.system == stdenv.hostPlatform.system,
  withPostgres ? stdenv.buildPlatform.system == stdenv.hostPlatform.system,
  boost187,
  sphinx,
  libmysqlclient,
  log4cplus,
  openssl,
  libpq,
  python3,
  mariadb,

  # tests
  nixosTests,
}:

stdenv.mkDerivation rec {
  pname = "kea";
  version = "3.0.0"; # only even minor versions are stable

  src = fetchurl {
    url = "https://ftp.isc.org/isc/${pname}/${version}/${pname}-${version}.tar.xz";
    hash = "sha256-v5Y9HhCVHYxXDGBCr8zyfHCdReA4E70mOde7HPxP7nY=";
  };

  outputs = [
    "out"
    "doc"
  ];

  mesonFlags = [
    "-Drunstatedir=/var"
    "-Dmysql=${if withMysql then "enabled" else "disabled"}"
    "-Dpostgresql=${if withPostgres then "enabled" else "disabled"}"

    # Disabled for now to move forward with kea-3.0.0. Requires extra dependencies
    "-Dnetconf=disabled"
  ];
  
  postUnpack = ''
    patchShebangs kea-3.0.0/scripts/grabber.py
  '';

  postConfigure = ''
    # Mangle embedded paths to dev-only inputs.
    sed -e "s|$NIX_STORE/[a-z0-9]\{32\}-|$NIX_STORE/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-|g" -i config.report
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    sphinx
  ]
  ++ (with python3Packages; [
    sphinx-rtd-theme
  ])
  ++ lib.optional withPostgres libpq
  ++ lib.optional withMysql mariadb;

  sphinxBuilders = [
    "html"
    "man"
  ];
  sphinxRoot = "doc/sphinx";

  buildInputs = [
    boost187
    libmysqlclient
    log4cplus
    openssl
    python3
  ];

  enableParallelBuilding = true;

  passthru.tests = {
    kea = nixosTests.kea;
    prefix-delegation = nixosTests.systemd-networkd-ipv6-prefix-delegation;
    networking-scripted = lib.recurseIntoAttrs {
      inherit (nixosTests.networking.scripted) dhcpDefault dhcpSimple dhcpOneIf;
    };
    networking-networkd = lib.recurseIntoAttrs {
      inherit (nixosTests.networking.networkd) dhcpDefault dhcpSimple dhcpOneIf;
    };
  };

  meta = {
    # May work with current versions of kea derivation but has not been confirmed
    # Previous error: implicit instantiation of undefined template 'std::char_traits<unsigned char>'
    broken = stdenv.buildPlatform.system == "x86_64-darwin";
    changelog = "https://downloads.isc.org/isc/kea/${version}/Kea-${version}-ReleaseNotes.txt";
    homepage = "https://kea.isc.org/";
    description = "High-performance, extensible DHCP server by ISC";
    longDescription = ''
      Kea is a new open source DHCPv4/DHCPv6 server being developed by
      Internet Systems Consortium. The objective of this project is to
      provide a very high-performance, extensible DHCP server engine for
      use by enterprises and service providers, either as is or with
      extensions and modifications.
    '';
    license = lib.licenses.mpl20;
    platforms = lib.platforms.unix;
    maintainers = with lib.maintainers; [
      fpletz
      hexa
    ];
  };
}
