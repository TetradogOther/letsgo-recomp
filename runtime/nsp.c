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
        if (plat_unpack(path, out_dir, NULL) != 0) {
            snprintf(why, why_size, "can't unpack the 7z (it needs bsdtar: the libarchive-tools package)");
            return NSP_ERR_IO;
        }
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
    if (find_exefs(out_dir, ex, sizeof ex, 0) && code_encrypted(ex)) {
        snprintf(why, why_size, "the game's code is encrypted (it needs the console's keys)");
        return NSP_ERR_ENCRYPTED;
    }
    return NSP_OK;
}
