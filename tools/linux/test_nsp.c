// test_nsp.c: the runtime's unpacking of a package (runtime/nsp.c), checked with a synthetic container.
//
//   tools/linux/make_test_nsp.py /tmp/test.nsp && tools/linux/test_nsp /tmp/test.nsp
//
// It links the runtime's nsp.c (and the platform layer for plat_unpack).
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>

#include "../../runtime/nsp.h"

// The platform layer's crash handler calls these (runtime/dispatch.c): not needed here
const char *rt_host_fn_name(uint64_t pc, uint64_t *offset) { (void)pc; (void)offset; return NULL; }
bool rt_fault_watch(uint64_t fa, uint64_t pc) { (void)fa; (void)pc; return false; }
void rt_fault_report(const char *what, uint64_t fa, uint64_t pc, uint64_t lr) {
    (void)what; (void)fa; (void)pc; (void)lr;
    exit(1);
}

static int fails;

static void check(bool ok, const char *what) {
    printf("%-46s %s\n", what, ok ? "ok" : "FAIL");
    if (!ok) fails++;
}

static bool is_file(const char *p) {
    struct stat st;
    return stat(p, &st) == 0 && S_ISREG(st.st_mode);
}

int main(int argc, char **argv) {
    if (argc < 2) { printf("usage: test_nsp <file.nsp>\n"); return 1; }
    const char *path = argv[1];
    char out[1024], why[256] = "";
    snprintf(out, sizeof out, "/tmp/test_nsp_out");
    system("rm -rf /tmp/test_nsp_out");

    int rc = nsp_extract(path, out, why, sizeof why);
    printf("nsp_extract: %d (%s)\n", rc, why);
    if (rc == NSP_ERR_ENCRYPTED) {
        // an encrypted package: the files may be out, but the runtime must say the keys are needed
        check(strstr(why, "keys") != NULL, "the message says the keys are needed");
        printf("%s\n", fails ? "NOT OK" : "OK");
        return fails ? 1 : 0;
    }
    check(rc == NSP_OK, "the package was unpacked");
    char p[1200];
    snprintf(p, sizeof p, "%s/main", out);
    check(is_file(p), "the exefs' main is out");
    snprintf(p, sizeof p, "%s/main.npdm", out);
    check(is_file(p), "the exefs' main.npdm is out");
    snprintf(p, sizeof p, "%s/romfs.bin", out);
    check(is_file(p), "the romfs.bin is out");
    snprintf(p, sizeof p, "%s/English", out);
    check(is_file(p), "the language file is out");
    // the exefs' folder, where the runtime looks for the code
    char ex[1024];
    check(nsp_find_exefs(out, ex, sizeof ex), "the exefs' folder is found");
    printf("%s\n", fails ? "NOT OK" : "OK");
    return fails ? 1 : 0;
}
