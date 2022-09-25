{ lib, stdenv, fetchurl, alsaLib, dbus, ffmpeg, libGL, libpulseaudio, libva
, openssl, udev, xorg, wayland }:

stdenv.mkDerivation {
  pname = "parsec";
  version = "2021-01-12";

  src = fetchurl {
    url = "https://builds.parsecgaming.com/package/parsec-linux.deb";
    sha256 = "sha256-DHIH9Bk3f8NeMESKzQDYcBMArFpEk2rG2HpGjJr8zcE=";
  };

  # The upstream deb package is out of date and doesn't work out of the box
  # anymore due to api.parsecgaming.com being down. Auto-updating doesn't work
  # because it doesn't patchelf the dynamic dependencies. Instead, "manually"
  # fetch the latest binaries.
  latest_appdata = fetchurl {
    url = "https://builds.parsecgaming.com/channel/release/appdata/linux/latest";
    sha256 = "sha256-fR8Wjkq4iNEQ3Ks1nssa5ii+5zHCtoym6J8sjDYCbLs=";
  };
  latest_parsecd_so = fetchurl {
    url ="https://builds.parsecgaming.com/channel/release/binary/linux/gz/parsecd-150-85c.so";
    sha256 = "sha256-6LCg958yHYnMknIDC+GPq2HBl95sKeNQvRxuXbPIpYg=";
  };

  postPatch = ''
    cp $latest_appdata usr/share/parsec/skel/appdata.json
    cp $latest_parsecd_so usr/share/parsec/skel/parsecd-150-85c.so
  '';

  runtimeDependencies = [
    alsaLib (lib.getLib dbus) libGL libpulseaudio libva.out
    (lib.getLib openssl) (lib.getLib stdenv.cc.cc) (lib.getLib udev)
    xorg.libX11 xorg.libXcursor xorg.libXi xorg.libXinerama xorg.libXrandr
    xorg.libXScrnSaver wayland (lib.getLib ffmpeg)
  ];

  unpackPhase = ''
    ar p "$src" data.tar.xz | tar xJ
  '';

  installPhase = ''
    mkdir -p $out/bin $out/libexec
    cp usr/bin/parsecd $out/libexec
    cp -r usr/share/parsec/skel $out/libexec
    # parsecd is a small wrapper binary which copies skel/* to ~/.parsec and
    # then runs from there. Unfortunately, it hardcodes the /usr/share/parsec
    # path, and patching that would be annoying. Instead, just reproduce the
    # install logic in a wrapper script.
    cat >$out/bin/parsecd <<EOF
    #! /bin/sh
    mkdir -p \$HOME/.parsec
    ln -sf $out/libexec/skel/* \$HOME/.parsec
    exec $out/libexec/parsecd "\$@"
    EOF
    chmod +x $out/bin/parsecd
  '';

  postFixup = ''
    # We do not use autoPatchelfHook since we need runtimeDependencies rpath to
    # also be set on the .so, not just on the main executable.
    patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
        $out/libexec/parsecd
    rpath=""
    for dep in $runtimeDependencies; do
      rpath="$rpath''${rpath:+:}$dep/lib"
    done
    patchelf --set-rpath "$rpath" $out/libexec/parsecd
    patchelf --set-rpath "$rpath" $out/libexec/skel/*.so
  '';

  meta = with lib; {
    description = "Remotely connect to a gaming PC for a low latency remote computing experience";
    homepage = "https://parsecgaming.com/";
    license = licenses.unfree;
    maintainers = with maintainers; [ delroth ];
  };
}
