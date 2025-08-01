{
  stdenv,
  lib,
  fetchFromGitHub,
  fetchpatch,
  fetchpatch2,
  fetchurl,
}:

# This file is responsible for fetching the sage source and adding necessary patches.
# It does not actually build anything, it just copies the patched sources to $out.
# This is done because multiple derivations rely on these sources and they should
# all get the same sources with the same patches applied.

stdenv.mkDerivation rec {
  version = "10.6";
  pname = "sage-src";

  src = fetchFromGitHub {
    owner = "sagemath";
    repo = "sage";
    rev = version;
    hash = "sha256-ZDYFq2lJXjnADFdX6y7sskaF0rkT5EIcdN8/bs00TlQ=";
  };

  # contains essential files (e.g., setup.cfg) generated by the bootstrap script.
  # TODO: investigate https://github.com/sagemath/sage/pull/35950
  configure-src = fetchurl {
    # the hash below is the tagged commit's _parent_. it can also be found by looking for
    # the "configure" asset at https://github.com/sagemath/sage/releases/tag/${version}
    url = "mirror://sageupstream/configure/configure-10741006a4794b7db82942db55b97033d5905431.tar.gz";
    hash = "sha256-7LqY+vwBlyukDfcRtuR99vpC3hcBo8WRUuJjiFFq9xk=";
  };

  # Patches needed because of particularities of nix or the way this is packaged.
  # The goal is to upstream all of them and get rid of this list.
  nixPatches = [
    # Parallelize docubuild using subprocesses, fixing an isolation issue. See
    # https://groups.google.com/forum/#!topic/sage-packaging/YGOm8tkADrE
    ./patches/sphinx-docbuild-subprocesses.patch

    # After updating smypow to (https://github.com/sagemath/sage/issues/3360)
    # we can now set the cache dir to be within the .sage directory. This is
    # not strictly necessary, but keeps us from littering in the user's HOME.
    ./patches/sympow-cache.patch
  ]
  ++ lib.optionals (stdenv.cc.isClang) [
    # https://github.com/NixOS/nixpkgs/pull/264126
    # Dead links in python sysconfig cause LLVM linker warnings, leading to cython doctest failures.
    ./patches/silence-linker.patch

    # Stack overflows during doctests; this does not change functionality.
    ./patches/disable-singular-doctest.patch
  ];

  # Since sage unfortunately does not release bugfix releases, packagers must
  # fix those bugs themselves. This is for critical bugfixes, where "critical"
  # == "causes (transient) doctest failures / somebody complained".
  bugfixPatches = [
    # compile libs/gap/element.pyx with -O1
    # a more conservative version of https://github.com/sagemath/sage/pull/37951
    ./patches/gap-element-crash.patch
  ];

  # Patches needed because of package updates. We could just pin the versions of
  # dependencies, but that would lead to rebuilds, confusion and the burdons of
  # maintaining multiple versions of dependencies. Instead we try to make sage
  # compatible with never dependency versions when possible. All these changes
  # should come from or be proposed to upstream. This list will probably never
  # be empty since dependencies update all the time.
  packageUpgradePatches = [
    # https://github.com/sagemath/sage/pull/39737, positively reviewed
    (fetchpatch {
      name = "sphinx-8.2-update.patch";
      url = "https://github.com/sagemath/sage/pull/39737/commits/4e485497fb5e20a056ffd2178360b88f482447d8.patch";
      hash = "sha256-oIcFeol0SW5dE/iE6mbYyas3kXIjOwsG1k+h99R94x8=";
    })

    # https://github.com/sagemath/sage/pull/40285, landed in 10.7.beta7
    (fetchpatch2 {
      name = "scipy-1.16-update.patch";
      url = "https://github.com/sagemath/sage/commit/d0cbe9d353722580f98a327694f1a361c9b83ccd.patch?full_index=1";
      hash = "sha256-uV2nttxCKDsNqMf1O+lUmuoiDrx7/CfiS00JBb9kiM8=";
    })
  ];

  patches = nixPatches ++ bugfixPatches ++ packageUpgradePatches;

  # do not create .orig backup files if patch applies with fuzz
  patchFlags = [
    "--no-backup-if-mismatch"
    "-p1"
  ];

  # harmless broken symlinks to (not) generated files used by sage-the-distro
  dontCheckForBrokenSymlinks = true;

  postPatch = ''
    # Make sure sage can at least be imported without setting any environment
    # variables. It won't be close to feature complete though.
    sed -i \
      "s|var(\"SAGE_ROOT\".*|var(\"SAGE_ROOT\", \"$out\")|" \
      src/sage/env.py

    # sage --docbuild unsets JUPYTER_PATH, which breaks our docbuilding
    # https://trac.sagemath.org/ticket/33650#comment:32
    sed -i "/export JUPYTER_PATH/d" src/bin/sage
  '';

  buildPhase = "# do nothing";

  installPhase = ''
    cp -r . "$out"
    tar xzf ${configure-src} -C "$out"
    rm "$out/configure"
  '';
}
