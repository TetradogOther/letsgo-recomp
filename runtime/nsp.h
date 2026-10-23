// The game's own files from a package (runtime/nsp.c): a .nsp (the PFS0 container) or a 7z with one inside.
//
// The container is not encrypted: it is unpacked here, no keys needed. The game's code (the NSO files) may be
// encrypted with the title key, though - then the files are of no use without the console's keys, and this says so
// instead of failing later with a cryptic error.
#pragma once
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    NSP_OK = 0,
    NSP_ERR_FORMAT,      // not a container we know (not a PFS0, not a 7z)
    NSP_ERR_ENCRYPTED,   // the game's code is encrypted (it needs the console's keys)
    NSP_ERR_IO,          // can't read it / can't write the files out
};

// Unpacks the package at path into out_dir (created). The result: the exefs (main, main.npdm, rtld, sdk, subsdk0,
// subsdk1) and the RomFS, where they were in the package. NSP_OK, or one of the errors above (why says which).
int nsp_extract(const char *path, const char *out_dir, char *why, size_t why_size);
// The folder with the exefs (main + main.npdm) in what was unpacked, "" if there is none.
bool nsp_find_exefs(const char *dir, char *out, size_t n);

#ifdef __cplusplus
}
#endif
