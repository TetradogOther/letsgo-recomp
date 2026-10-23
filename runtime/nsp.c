// The game's own files from a package (runtime/nsp.h): a .nsp (the PFS0 container) or a 7z with one inside.
//
// The container is not encrypted: it is unpacked here, no keys needed. The game's code (the NSO files) may be
// encrypted with the title key, though - then the files are of no use without the console's keys, and this says so
// instead of failing later with a cryptic error.
#include "nsp.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>  // strcasecmp
#include <sys/stat.h>

#include "platform.h"

static bool is_file(const char *p) {
    struct stat st;
    return stat(p, &st) == 0 && S_ISREG(st.st_mode);
}

static bool is_dir(const char *p) {
    struct stat st;
    return stat(p, &st) == 0 && S_ISDIR(st.st_mode);
}

// The folders of a path (the ones before the file name), made
static void make_parents(const char *path) {
    char buf[1024];
    snprintf(buf, sizeof buf, "%s", path);
    for (char *c = buf + 1; *c; c++)
        if (*c == '/' || *c == '\\') {
            char s = *c;
            *c = 0;
            mkdir(buf, 0755);
            *c = s;
        }
}

// ---- PFS0 (the .nsp container)
// The header, the file table (an offset, a size and a name, per file), the names, then the data.
typedef struct {
    uint64_t off, size;
    uint32_t soff, ssize;
} PfsEntry;

static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t rd64(const uint8_t *p) {
    return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32);
}

// Copies one file of the container
static bool copy_out(FILE *in, uint64_t off, uint64_t size, const char *dst) {
    make_parents(dst);
    FILE *out = fopen(dst, "wb");
    if (!out) return false;
    if (fseek(in, (long)off, SEEK_SET) != 0) { fclose(out); return false; }
    uint8_t buf[1 << 16];
    uint64_t left = size;
    while (left) {
        size_t n = sizeof buf < left ? sizeof buf : (size_t)left;
        if (fread(buf, 1, n, in) != n) { fclose(out); return false; }
        if (fwrite(buf, 1, n, out) != n) { fclose(out); return false; }
        left -= n;
    }
    fclose(out);
    return true;
}

static int pfs0_extract(const char *path, const char *out_dir, char *why, size_t why_size) {
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(why, why_size, "can't read %s", path); return NSP_ERR_IO; }
    uint8_t head[16];
    if (fread(head, 1, sizeof head, f) != sizeof head || memcmp(head, "PFS0", 4)) {
        fclose(f);
        snprintf(why, why_size, "not a PFS0 container");
        return NSP_ERR_FORMAT;
    }
    uint32_t count = rd32(head + 4), strsize = rd32(head + 8);
    if (!count || count > 100000 || strsize > (1u << 26)) {
        fclose(f);
        snprintf(why, why_size, "the container's file table is not readable");
        return NSP_ERR_FORMAT;
    }
    PfsEntry *ents = (PfsEntry *)calloc(count, sizeof *ents);
    uint8_t *raw = (uint8_t *)malloc((size_t)count * 0x18);
    if (!ents || !raw || fread(raw, 0x18, count, f) != count) {  // (fread returns the items read)
        free(ents);
        free(raw);
        fclose(f);
        snprintf(why, why_size, "the container's file table is not readable");
        return NSP_ERR_FORMAT;
    }
    for (uint32_t i = 0; i < count; i++) {
        ents[i].off = rd64(raw + (size_t)i * 0x18);
        ents[i].size = rd64(raw + (size_t)i * 0x18 + 8);
        ents[i].soff = rd32(raw + (size_t)i * 0x18 + 16);
        ents[i].ssize = rd32(raw + (size_t)i * 0x18 + 20);
    }
    free(raw);
    char *strs = (char *)malloc(strsize + 1);
    if (!strs || fread(strs, 1, strsize, f) != strsize) {
        free(ents);
        free(strs);
        fclose(f);
        snprintf(why, why_size, "the container's names are not readable");
        return NSP_ERR_FORMAT;
    }
    strs[strsize] = 0;
    long data_start = ftell(f);
    int rc = NSP_OK;
    for (uint32_t i = 0; i < count && rc == NSP_OK; i++) {
        if (ents[i].soff + ents[i].ssize > strsize) { rc = NSP_ERR_FORMAT; break; }
        char name[512];
        uint32_t n = ents[i].ssize < sizeof name - 1 ? ents[i].ssize : (uint32_t)sizeof name - 1;
        memcpy(name, strs + ents[i].soff, n);
        name[n] = 0;
        if (!name[0] || name[0] == '/' || strstr(name, "..")) { rc = NSP_ERR_FORMAT; break; }  // (a path that escapes)
        char dst[1024];
        snprintf(dst, sizeof dst, "%s/%s", out_dir, name);
        if (!copy_out(f, (uint64_t)data_start + ents[i].off, ents[i].size, dst)) {
            snprintf(why, why_size, "can't write %s", name);
            rc = NSP_ERR_IO;
        }
    }
    free(ents);
    free(strs);
    fclose(f);
    if (rc != NSP_OK && !why[0]) snprintf(why, why_size, "the container's files are not readable");
    return rc;
}

// The password of an archive that asks for one (the repacks often encrypt the file list)
static char g_password[256];

void nsp_set_password(const char *pw) {
    snprintf(g_password, sizeof g_password, "%s", pw ? pw : "");
}

// ---- the game's code: encrypted or not
// The NSO header's flags: the first bit says the file is encrypted with the title key.
static bool code_encrypted(const char *dir) {
    char p[1024];
    snprintf(p, sizeof p, "%s/main", dir);
    FILE *f = fopen(p, "rb");
    if (!f) return false;
    uint8_t head[16];
    bool enc = false;
    if (fread(head, 1, sizeof head, f) == sizeof head && !memcmp(head, "NSO0", 4)) enc = (rd32(head + 0x0C) & 1) != 0;
    fclose(f);
    return enc;
}

// The folder with the exefs (main + main.npdm), in what was unpacked
static bool find_exefs(const char *dir, char *out, size_t n, int depth) {
    char p[1024];
    snprintf(p, sizeof p, "%s/main.npdm", dir);
    if (is_file(p)) {
        snprintf(p, sizeof p, "%s/main", dir);
        if (is_file(p)) {
            snprintf(out, n, "%s", dir);
            return true;
        }
    }
    if (depth > 3) return false;
    DIR *d = opendir(dir);
    if (!d) return false;
    struct dirent *e;
    bool found = false;
    while (!found && (e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
        if (is_dir(p)) found = find_exefs(p, out, n, depth + 1);
    }
    closedir(d);
    return found;
}

// A content archive (.nca)? the "layered" packages hold the game in them, encrypted with the console's keys
static bool has_nca(const char *dir, int depth) {
    DIR *d = opendir(dir);
    if (!d) return false;
    struct dirent *e;
    bool found = false;
    while (!found && (e = readdir(d))) {
        const char *n = e->d_name;
        size_t len = strlen(n);
        if (len > 4 && !strcasecmp(n + len - 4, ".nca")) { found = true; break; }
        if (depth < 2) {
            char p[1024];
            snprintf(p, sizeof p, "%s/%s", dir, n);
            if (n[0] != '.' && is_dir(p)) found = has_nca(p, depth + 1);
        }
    }
    closedir(d);
    return found;
}

bool nsp_find_exefs(const char *dir, char *out, size_t n) { return find_exefs(dir, out, n, 0); }

// Copies a file or a folder (the game's parts that were in the package)
static bool copy_tree(const char *src, const char *dst) {
    struct stat st;
    if (stat(src, &st) != 0) return false;
    if (S_ISDIR(st.st_mode)) {
        mkdir(dst, 0755);
        DIR *d = opendir(src);
        if (!d) return false;
        struct dirent *e;
        bool ok = true;
        while (ok && (e = readdir(d))) {
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
            char s[1024], t[1024];
            snprintf(s, sizeof s, "%s/%s", src, e->d_name);
            snprintf(t, sizeof t, "%s/%s", dst, e->d_name);
            ok = copy_tree(s, t);
        }
        closedir(d);
        return ok;
    }
    FILE *in = fopen(src, "rb");
    if (!in) return false;
    FILE *out = fopen(dst, "wb");
    if (!out) { fclose(in); return false; }
    char buf[1 << 16];
    size_t n;
    bool ok = true;
    while ((n = fread(buf, 1, sizeof buf, in)) > 0)
        if (fwrite(buf, 1, n, out) != n) { ok = false; break; }
    fclose(in);
    fclose(out);
    return ok;
}

// A 7z with an encrypted file list: libarchive can't read those (only the 7z program can), so it is tried too.
static int unpack_7z(const char *path, const char *out_dir, char *why, size_t why_size) {
    int r = plat_unpack(path, out_dir, NULL);
    if (r == 0) return 0;
    char pw[300], out[1200];
    snprintf(pw, sizeof pw, "-p%s", g_password);
    snprintf(out, sizeof out, "-o%s", out_dir);  // (-o and the folder are one argument)
    const char *argv[] = {"7z", "x", "-y", pw, out, path, NULL};
    PlatProc p = plat_spawn(argv, NULL, false);
    if (p) {
        int r2 = plat_proc_wait(p, true);
        if (r2 == 0) return 0;
        if (r < 0) r = r2;
    }
    snprintf(why, why_size, g_password[0] ? "can't unpack the 7z (wrong password, or the file is damaged or incomplete)"
                                           : "can't unpack the 7z (it needs the 7z program, or the file is damaged)");
    return r;
}

// The files of the package, in a folder: the container (7z, zip) unpacked, and, if there was a .nsp inside, its
// contents too (the .nca files).
static int unpack_package(const char *path, const char *dir, char *why, size_t why_size) {
    mkdir(dir, 0755);
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(why, why_size, "can't read %s", path); return NSP_ERR_IO; }
    uint8_t head[8];
    size_t got = fread(head, 1, sizeof head, f);
    fclose(f);
    if (got >= 4 && !memcmp(head, "PFS0", 4)) return pfs0_extract(path, dir, why, why_size);
    if (got >= 6 && !memcmp(head, "7z\xbc\xaf\x27\x1c", 6)) return unpack_7z(path, dir, why, why_size) ? NSP_OK : NSP_ERR_IO;
    // a zip: the system's archiver
    if (got >= 2 && head[0] == 'P' && head[1] == 'K') {
        if (plat_unpack(path, dir, NULL) == 0) return NSP_OK;
        snprintf(why, why_size, "can't unpack the zip");
        return NSP_ERR_IO;
    }
    snprintf(why, why_size, "not a .nsp (PFS0), a 7z nor a zip");
    return NSP_ERR_FORMAT;
}

// The content archives (.nca) in a folder (in the package, or in the .nsp inside it)
static int find_nca(const char *dir, char out[][1200], int max, int depth) {
    int n = 0;
    DIR *d = opendir(dir);
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        const char *name = e->d_name;
        if (name[0] == '.') continue;
        char p[1200];
        snprintf(p, sizeof p, "%s/%s", dir, name);
        size_t len = strlen(name);
        if (len > 4 && !strcasecmp(name + len - 4, ".nca")) {
            if (strstr(name, "cnmt")) continue;  // (the meta: no game inside)
            if (n < max) snprintf(out[n++], 1200, "%s", p);
        } else if (depth > 0 && is_dir(p))
            n += find_nca(p, out + n, max - n, depth - 1);
    }
    closedir(d);
    return n;
}

// The exefs' folder (main + main.npdm) in a folder, if it is there
static bool find_exefs_in(const char *dir, char *out, size_t n, int depth) {
    char p[1200];
    snprintf(p, sizeof p, "%s/main.npdm", dir);
    if (is_file(p)) {
        snprintf(p, sizeof p, "%s/main", dir);
        if (is_file(p)) {
            snprintf(out, n, "%s", dir);
            return true;
        }
    }
    if (depth > 2) return false;
    DIR *d = opendir(dir);
    if (!d) return false;
    struct dirent *e;
    bool found = false;
    while (!found && (e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
        if (is_dir(p)) found = find_exefs_in(p, out, n, depth + 1);
    }
    closedir(d);
    return found;
}

// ---- decrypting with hactool
// The game's code and data are encrypted with the console's keys: hactool (the user's own program) does the
// decryption, with the keys file the user dumped from their console. This only runs it.
static bool run(const char *const argv[], int *code) {
    PlatProc p = plat_spawn(argv, NULL, false);
    if (!p) { *code = -1; return false; }
    *code = plat_proc_wait(p, true);
    return true;
}

int nsp_decrypt(const char *package, const char *keys, const char *hactool, const char *out_dir, char *why, size_t why_size) {
    why[0] = 0;
    if (!keys || !keys[0]) { snprintf(why, why_size, "no keys file"); return NSP_ERR_FORMAT; }
    if (!hactool || !hactool[0]) { snprintf(why, why_size, "no hactool"); return NSP_ERR_FORMAT; }
    char work[1200], exefs[1200], romfs[1200];
    int code = 0;
    snprintf(work, sizeof work, "%s/pkg", out_dir);
    snprintf(exefs, sizeof exefs, "%s/exefs", out_dir);
    snprintf(romfs, sizeof romfs, "%s/romfs", out_dir);
    mkdir(out_dir, 0755);

    // 1. the container: the package unpacked (7z, zip) and, if there was a .nsp inside, its contents
    int rc = unpack_package(package, work, why, why_size);
    if (rc != NSP_OK) return rc;

    // 2. the content archives (.nca): each one has the code (the exefs) and the data (the RomFS)
    char nca[16][1200];
    int nnca = find_nca(work, nca, 16, 3);
    for (int i = 0; i < nnca; i++) {
        char ex[1300], ro[1300];
        snprintf(ex, sizeof ex, "--exefsdir=%s", exefs);
        snprintf(ro, sizeof ro, "--romfsdir=%s", romfs);
        const char *args[] = {hactool, "-k", keys, ex, ro, nca[i], NULL};
        if (!run(args, &code) || code != 0) {
            snprintf(why, why_size, "hactool could not decrypt %s (%d): are the keys the right ones?",
                     strrchr(nca[i], '/') + 1, code);
            return NSP_ERR_ENCRYPTED;
        }
    }
    // 3. the exefs, if they were not in a content archive (a package with the ExeFS loose)
    if (!nnca && !find_exefs_in(work, exefs, sizeof exefs, 2)) {
        snprintf(why, why_size, "no game content in the package");
        return NSP_ERR_FORMAT;
    }
    return NSP_OK;
}

int nsp_extract(const char *path, const char *out_dir, char *why, size_t why_size) {
    why[0] = 0;
    mkdir(out_dir, 0755);
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(why, why_size, "can't read %s", path); return NSP_ERR_IO; }
    uint8_t head[8];
    size_t got = fread(head, 1, sizeof head, f);
    fclose(f);

    if (got >= 4 && !memcmp(head, "PFS0", 4)) {
        int rc = pfs0_extract(path, out_dir, why, why_size);
        if (rc != NSP_OK) return rc;
    } else if (got >= 6 && !memcmp(head, "7z\xbc\xaf\x27\x1c", 6)) {
        // a 7z: unpacked with the system's archiver (bsdtar on Linux, tar.exe on Windows)
        int r = unpack_7z(path, out_dir, why, why_size);
        if (r != 0) return NSP_ERR_IO;
        // a .nsp inside it? then that one is the container: its files are copied next to the 7z's ones
        DIR *d = opendir(out_dir);
        if (d) {
            struct dirent *e;
            while ((e = readdir(d))) {
                if (e->d_name[0] == '.') continue;
                char p[1024];
                snprintf(p, sizeof p, "%s/%s", out_dir, e->d_name);
                if (!is_file(p)) continue;
                FILE *g = fopen(p, "rb");
                if (!g) continue;
                uint8_t h[4];
                size_t n = fread(h, 1, 4, g);
                fclose(g);
                if (n != 4 || memcmp(h, "PFS0", 4)) continue;
                char sub[1024];
                snprintf(sub, sizeof sub, "%s/nsp", out_dir);
                mkdir(sub, 0755);
                int rc = pfs0_extract(p, sub, why, why_size);
                if (rc != NSP_OK) { closedir(d); return rc; }
                DIR *e2 = opendir(sub);
                if (e2) {
                    struct dirent *x;
                    while ((x = readdir(e2))) {
                        if (x->d_name[0] == '.') continue;
                        char from[1024], to[1024];
                        snprintf(from, sizeof from, "%s/%s", sub, x->d_name);
                        snprintf(to, sizeof to, "%s/%s", out_dir, x->d_name);
                        copy_tree(from, to);
                    }
                    closedir(e2);
                }
                break;
            }
            closedir(d);
        }
    } else {
        snprintf(why, why_size, "not a .nsp (PFS0) nor a 7z");
        return NSP_ERR_FORMAT;
    }

    // the game's code: encrypted with the title key? then it is of no use without the console's keys
    char ex[1024];
    if (find_exefs(out_dir, ex, sizeof ex, 0)) {
        if (code_encrypted(ex)) {
            snprintf(why, why_size, "the game's code is encrypted (it needs the console's keys)");
            return NSP_ERR_ENCRYPTED;
        }
        return NSP_OK;
    }
    // no exefs: a "layered" package? the game is inside content archives (.nca), encrypted with the console's keys
    if (has_nca(out_dir, 0)) {
        snprintf(why, why_size, "the package holds encrypted content (.nca): it needs the console's keys");
        return NSP_ERR_ENCRYPTED;
    }
    return NSP_OK;
}
