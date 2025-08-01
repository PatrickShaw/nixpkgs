{
  stdenv,
  fetchurl,
  fetchpatch,
  lib,
  pkg-config,
  util-linux,
  libcap,
  libtirpc,
  libevent,
  sqlite,
  libkrb5,
  kmod,
  libuuid,
  keyutils,
  lvm2,
  systemd,
  coreutils,
  tcp_wrappers,
  python3,
  buildPackages,
  nixosTests,
  rpcsvc-proto,
  openldap,
  cyrus_sasl,
  libxml2,
  udevCheckHook,
  enablePython ? true,
  enableLdap ? true,
}:

let
  statdPath = lib.makeBinPath [
    systemd
    util-linux
    coreutils
  ];
in

stdenv.mkDerivation rec {
  pname = "nfs-utils";
  version = "2.7.1";

  src = fetchurl {
    url = "mirror://kernel/linux/utils/nfs-utils/${version}/${pname}-${version}.tar.xz";
    hash = "sha256-iFyUioSli8pBSPRZWI+ac2nbtA3MRm8E5FXGsQ/Qqkg=";
  };

  # libnfsidmap is built together with nfs-utils from the same source,
  # put it in the "lib" output, and the headers in "dev"
  outputs = [
    "out"
    "dev"
    "lib"
    "man"
  ];

  nativeBuildInputs = [
    pkg-config
    buildPackages.stdenv.cc
    rpcsvc-proto
    udevCheckHook
  ];

  buildInputs = [
    libtirpc
    libcap
    libevent
    sqlite
    lvm2
    libuuid
    keyutils
    libkrb5
    tcp_wrappers
    libxml2
  ]
  ++ lib.optional enablePython python3
  ++ lib.optionals enableLdap [
    openldap
    cyrus_sasl
  ];

  enableParallelBuilding = true;

  preConfigure = ''
    substituteInPlace configure \
      --replace '$dir/include/gssapi' ${lib.getDev libkrb5}/include/gssapi \
      --replace '$dir/bin/krb5-config' ${lib.getDev libkrb5}/bin/krb5-config
  '';

  configureFlags = [
    "--with-start-statd=${placeholder "out"}/bin/start-statd"
    "--enable-gss"
    "--enable-svcgss"
    "--with-statedir=/var/lib/nfs"
    "--with-krb5=${lib.getLib libkrb5}"
    "--with-systemd=${placeholder "out"}/etc/systemd/system"
    "--enable-libmount-mount"
    "--with-pluginpath=${placeholder "lib"}/lib/libnfsidmap" # this installs libnfsidmap
    "--with-rpcgen=${buildPackages.rpcsvc-proto}/bin/rpcgen"
    "--with-modprobedir=${placeholder "out"}/etc/modprobe.d"
  ]
  ++ lib.optional enableLdap "--enable-ldap";

  patches = lib.optionals stdenv.hostPlatform.isMusl [
    # http://openwall.com/lists/musl/2015/08/18/10
    (fetchpatch {
      url = "https://raw.githubusercontent.com/alpinelinux/aports/cb880042d48d77af412d4688f24b8310ae44f55f/main/nfs-utils/musl-getservbyport.patch";
      sha256 = "1fqws9dz8n1d9a418c54r11y3w330qgy2652dpwcy96cm44sqyhf";
    })
    (fetchpatch {
      url = "https://raw.githubusercontent.com/void-linux/void-packages/bb636cdb1b274f44d92b1cb2fdf0dff6079f97aa/srcpkgs/nfs-utils/patches/nfs-utils-2.7.1-define_macros_for_musl.patch";
      hash = "sha256-wsyioRjzs1PObMHwYgf5h/Ngv+s5MPsroAuUNGs9lR0=";
    })
    (fetchpatch {
      url = "https://raw.githubusercontent.com/void-linux/void-packages/bb636cdb1b274f44d92b1cb2fdf0dff6079f97aa/srcpkgs/nfs-utils/patches/musl-svcgssd-sysconf.patch";
      hash = "sha256-3TXgqswxlhFqXRPcjwo4MdqlTYl+dWVaa0E5r9Mnw18=";
    })
    (fetchpatch {
      url = "https://raw.githubusercontent.com/void-linux/void-packages/bb636cdb1b274f44d92b1cb2fdf0dff6079f97aa/srcpkgs/nfs-utils/patches/musl-fix_long_unsigned_int.patch";
      hash = "sha256-rS6sqqoGLIaPVq04+QiqP4qa88i1z4ZZCssM5k/XQ68=";
    })
  ];

  postPatch = ''
    patchShebangs tests
    sed -i "s,/usr/sbin,$out/bin,g" utils/statd/statd.c
    sed -i "s,^PATH=.*,PATH=$out/bin:${statdPath}," utils/statd/start-statd

    substituteInPlace systemd/nfs-utils.service \
      --replace "/bin/true" "${coreutils}/bin/true"

    substituteInPlace tools/nfsrahead/Makefile.in systemd/Makefile.in \
      --replace "/usr/lib/udev/rules.d/" "$out/lib/udev/rules.d/"

    substituteInPlace utils/mount/Makefile.in \
      --replace "chmod 4511" "chmod 0511"

    sed '1i#include <stdint.h>' -i support/nsm/rpc.c
  '';

  makeFlags = [
    "sbindir=$(out)/bin"
    "generator_dir=$(out)/etc/systemd/system-generators"
  ];

  doInstallCheck = true;

  installFlags = [
    "statedir=$(TMPDIR)"
    "statdpath=$(TMPDIR)"
  ];

  stripDebugList = [
    "lib"
    "libexec"
    "bin"
    "etc/systemd/system-generators"
  ];

  postInstall = ''
    # Not used on NixOS
    sed -i \
      -e "s,/sbin/modprobe,${kmod}/bin/modprobe,g" \
      -e "s,/usr/sbin,$out/bin,g" \
      $out/etc/systemd/system/*
  ''
  + lib.optionalString (!enablePython) ''
    # Remove all scripts that require python (currently mountstats and nfsiostat)
    grep -l /usr/bin/python $out/bin/* | xargs -I {} rm -v {}
  '';

  # One test fails on mips.
  # doCheck = !stdenv.hostPlatform.isMips;
  # https://bugzilla.kernel.org/show_bug.cgi?id=203793
  doCheck = false;

  disallowedReferences = [ (lib.getDev libkrb5) ];

  passthru.tests = {
    nfs3-simple = nixosTests.nfs3.simple;
    nfs4-simple = nixosTests.nfs4.simple;
    nfs4-kerberos = nixosTests.nfs4.kerberos;
  };

  meta = with lib; {
    description = "Linux user-space NFS utilities";

    longDescription = ''
      This package contains various Linux user-space Network File
      System (NFS) utilities, including RPC `mount' and `nfs'
      daemons.
    '';

    homepage = "https://linux-nfs.org/";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    maintainers = with maintainers; [ abbradar ];
  };
}
