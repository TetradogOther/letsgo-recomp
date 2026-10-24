# tools/linux/stage.sh: what the Linux packages (.deb and AppImage) have in common: building the runtime, the game
# code generator and the Zig compiler, and the tree they all go in.
#
# Sourced by build_deb.sh and build_appimage.sh (not run on its own).
#
# The caller's environment:
#   WITH_ZIG=1     the Zig compiler (the one that builds the game code on the player's machine) in the package
#   WITH_HELPER=1  the game code generator in the package (without it the package only shows the start screen)
#   JOBS=<n>       how many compilers at once
#   DEPS=<prefix>  a prefix with SDL3 / FFmpeg / shaderc to link against (the distribution's, by default: empty)
#   ARCH=amd64|arm64

PKG_BUILD=${PKG_BUILD:-build/pkg}
PKG_OBJ=$PKG_BUILD/obj
PKG_HELPER=$PKG_BUILD/helper
# the package's own folder name (runtime/paths.h: the runtime looks for its files there)
RT_PKG_DIR=$(sed -n 's/^#define RT_PKG_DIR "\(.*\)".*/\1/p' runtime/paths.h)

# the caller's environment (the defaults are here: every script that sources this one gets them)
WITH_ZIG=${WITH_ZIG:-1}       # the Zig compiler in the package
WITH_HELPER=${WITH_HELPER:-1}  # the game code generator in the package
JOBS=${JOBS:-$(nproc)}        # how many compilers at once
DEPS=${DEPS:-}                # a prefix with SDL3 / FFmpeg / shaderc (the distribution's, by default: empty)

# The architecture: the one of the machine, or the one asked for.
pkg_arch() {
    ARCH=${ARCH:-$(dpkg --print-architecture)}
    case "$ARCH" in
        amd64) ZIG_ARCH=x86_64; PKG_ARCH=amd64 ;;
        arm64) ZIG_ARCH=aarch64; PKG_ARCH=arm64 ;;
        *) echo "build: ARCH $ARCH not supported (amd64, arm64)"; exit 1 ;;
    esac
}

# The version of the app (runtime/paths.h).
pkg_app_version() {
    sed -n 's/^#define RT_APP_VERSION "\(.*\)".*/\1/p' runtime/paths.h
}

# 1. the runtime: the launcher and everything that stands in for the Switch. It links against the distribution's
#    libraries, so the package has no library of its own inside.
pkg_build_runtime() {
    echo "==> the runtime ($PKG_OBJ)"
    make -j"$JOBS" LD= DEPS="$DEPS" B="$PKG_OBJ" "$PKG_OBJ/lasrecomp"
}

# 2. the game code generator, frozen with PyInstaller (the start screen runs it on the player's own game files to
#    translate them into C; the player needs no Python).
pkg_build_helper() {
    [ "$WITH_HELPER" = 1 ] || return 0
    if [ ! -x "$PKG_HELPER/lasgen/lasgen" ]; then
        echo "==> the game code generator (PyInstaller)"
        python3 -m venv "$PKG_BUILD/venv"
        "$PKG_BUILD/venv/bin/pip" install -q --upgrade pip
        "$PKG_BUILD/venv/bin/pip" install -q capstone unicorn lz4 pyinstaller
        "$PKG_BUILD/venv/bin/python" -m PyInstaller --noconfirm --clean --log-level WARN \
            --distpath "$PKG_HELPER" --workpath "$PKG_BUILD/pyinstaller" tools/lasgen.spec
    fi
}

# 3. zig: the compiler the start screen builds the game code with on the player's machine (as on Windows).
pkg_fetch_zig() {
    [ "$WITH_ZIG" = 1 ] || return 0
    echo "==> zig (the compiler of the game code)"
    ZIG_TARGET=$ZIG_ARCH-linux bash tools/fetch_zig.sh
}

# The tree both packages share. $1: the root of the tree (the .deb's stage folder, the AppImage's AppDir).
pkg_stage_tree() {
    local root=$1
    echo "==> the package tree ($root)"
    rm -rf "$root"
    mkdir -p "$root/usr/bin" "$root/usr/lib/$RT_PKG_DIR" "$root/usr/share/letsgo-recomp" \
             "$root/usr/share/applications" "$root/usr/share/doc/letsgo-recomp" \
             "$root/usr/share/icons/hicolor/scalable/apps" "$root/usr/share/icons/hicolor/1024x1024/apps" \
             "$root/usr/share/man/man1" "$root/usr/share/metainfo"
    cp "$PKG_OBJ/lasrecomp" "$root/usr/bin/letsgo-recomp"
    chmod 755 "$root/usr/bin/letsgo-recomp"
    # the debug symbols (the backtrace's names come from the dynamic table, which strip keeps)
    strip --strip-unneeded "$root/usr/bin/letsgo-recomp" 2>/dev/null || true

    # what the program ships: the generator, the compiler and the headers the game code is built against. The
    # generator and the compiler depend on the architecture, so they go in <prefix>/lib/letsgo-recomp (the Debian
    # policy: the ones that depend on the architecture do not go in /usr/share)
    if [ "$WITH_HELPER" = 1 ]; then
        cp -a "$PKG_HELPER/lasgen" "$root/usr/lib/$RT_PKG_DIR/"
        # the debug symbols of the bundled libraries (unicorn, capstone): the helper doesn't need them
        find "$root/usr/lib/$RT_PKG_DIR/lasgen" \( -name "*.so" -o -name "*.so.*" \) -type f \
            -exec strip --strip-unneeded {} \; 2>/dev/null || true
    fi
    if [ "$WITH_ZIG" = 1 ]; then
        cp -a build/zig "$root/usr/lib/$RT_PKG_DIR/zig"
    fi
    mkdir -p "$root/usr/share/letsgo-recomp/gamelib-src"
    cp runtime/cpu.h runtime/simd.h runtime/simd_fp.h runtime/gamelib.h tools/gamelib_entry.c \
       runtime/hle/hle_symbols.txt "$root/usr/share/letsgo-recomp/gamelib-src/"
    cp docs/icon/icon_1024.png "$root/usr/share/letsgo-recomp/icon.png"
    cp docs/icon/icon.svg "$root/usr/share/icons/hicolor/scalable/apps/letsgo-recomp.svg"
    # the sizes a desktop asks for (tools/make_icons.py writes them; the 1024 one is the biggest)
    for s in 16 24 32 48 64 128 256 512; do
        d="$root/usr/share/icons/hicolor/${s}x${s}/apps"
        mkdir -p "$d"
        cp "docs/icon/hicolor/${s}x${s}/apps/letsgo-recomp.png" "$d/" 2>/dev/null || true
    done
    cp docs/icon/icon_1024.png "$root/usr/share/icons/hicolor/1024x1024/apps/letsgo-recomp.png"
    cp third_party/fonts/Baloo2/Baloo2-SemiBold.ttf "$root/usr/share/letsgo-recomp/"
    cp third_party/fonts/Baloo2/OFL.txt "$root/usr/share/letsgo-recomp/Baloo2-OFL.txt"
    cp LICENSE "$root/usr/share/doc/letsgo-recomp/LICENSE.txt"
    cp LICENSE-LASRecomp "$root/usr/share/doc/letsgo-recomp/LICENSE-LASRecomp.txt"
    cp docs/release-README.txt "$root/usr/share/doc/letsgo-recomp/README.txt"
    cp debian/copyright "$root/usr/share/doc/letsgo-recomp/copyright"
    cp debian/org.tetradogother.letsgo-recomp.desktop "$root/usr/share/applications/"
    cp debian/org.tetradogother.letsgo-recomp.metainfo.xml "$root/usr/share/metainfo/"
    # the manual page, compressed (the Debian policy)
    gzip -9n -c debian/letsgo-recomp.1 > "$root/usr/share/man/man1/letsgo-recomp.1.gz"

    find "$root" -type d -exec chmod 755 {} +
    find "$root" -type f -exec chmod 644 {} +   # (the copied programs keep their own mode: cp -a)
    chmod 755 "$root/usr/bin/letsgo-recomp"
    [ -f "$root/usr/lib/$RT_PKG_DIR/lasgen/lasgen" ] && chmod 755 "$root/usr/lib/$RT_PKG_DIR/lasgen/lasgen"
    [ -f "$root/usr/lib/$RT_PKG_DIR/zig/zig" ] && chmod 755 "$root/usr/lib/$RT_PKG_DIR/zig/zig"
}
