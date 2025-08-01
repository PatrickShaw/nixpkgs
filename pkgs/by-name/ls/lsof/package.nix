{
  lib,
  stdenv,
  fetchFromGitHub,
  buildPackages,
  perl,
  which,
  ncurses,
  nukeReferences,
  freebsd,
  ed,
}:

let
  dialect = lib.last (lib.splitString "-" stdenv.hostPlatform.system);
in

stdenv.mkDerivation rec {
  pname = "lsof";
  version = "4.99.5";

  src = fetchFromGitHub {
    owner = "lsof-org";
    repo = "lsof";
    rev = version;
    hash = "sha256-zn09cwFFz5ZNJu8GwGGSSGNx5jvXbKLT6/+Lcmn1wK8=";
  };

  postPatch = ''
    patchShebangs --build lib/dialects/*/Mksrc
    # Do not re-build version.h in every 'make' to allow nuke-refs below.
    # We remove phony 'FRC' target that forces rebuilds:
    #   'version.h: FRC ...' is translated to 'version.h: ...'.
    sed -i lib/dialects/*/Makefile -e 's/version.h:\s*FRC/version.h:/'
  ''
  # help Configure find libproc.h in $SDKROOT
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    sed -i -e 's|lcurses|lncurses|g' \
           -e "s|/Library.*/MacOSX.sdk/|\"$SDKROOT\"/|" Configure
  '';

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [
    nukeReferences
    perl
    which
    ed
  ];
  buildInputs = [ ncurses ];

  # Stop build scripts from searching global include paths
  LSOF_INCLUDE = "${lib.getDev stdenv.cc.libc}/include";
  configurePhase =
    let
      genericFlags = "LSOF_CC=$CC LSOF_AR=\"$AR cr\" LSOF_RANLIB=$RANLIB";
      linuxFlags = lib.optionalString stdenv.hostPlatform.isLinux "LINUX_CONF_CC=$CC_FOR_BUILD";
      freebsdFlags = lib.optionalString stdenv.hostPlatform.isFreeBSD "FREEBSD_SYS=${freebsd.sys.src}/sys";
    in
    "${genericFlags} ${linuxFlags} ${freebsdFlags} ./Configure -n ${dialect}";

  preBuild = ''
    for filepath in $(find dialects/${dialect} -type f); do
      sed -i "s,/usr/include,$LSOF_INCLUDE,g" $filepath
    done

    # Wipe out development-only flags from CFLAGS embedding
    make version.h
    nuke-refs version.h
  '';

  installPhase = ''
    # Fix references from man page https://github.com/lsof-org/lsof/issues/66
    substituteInPlace Lsof.8 \
      --replace ".so ./00DIALECTS" "" \
      --replace ".so ./version" ".ds VN ${version}"
    mkdir -p $out/bin $out/man/man8
    cp Lsof.8 $out/man/man8/lsof.8
    cp lsof $out/bin
  '';

  meta = {
    homepage = "https://github.com/lsof-org/lsof";
    description = "Tool to list open files";
    mainProgram = "lsof";
    longDescription = ''
      List open files. Can show what process has opened some file,
      socket (IPv6/IPv4/UNIX local), or partition (by opening a file
      from it).
    '';
    license = lib.licenses.purdueBsd;
    maintainers = with lib.maintainers; [ dezgeg ];
    platforms = lib.platforms.unix;
  };
}
