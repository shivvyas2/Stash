//
//  NetworkFix.c
//  Stash
//
//  Stands in for libSystem inside the classic engine's network driver (nsiproxy.so):
//  Stash points it at this library, which re-exports libSystem.
//
//  The driver looks up net.inet.tcp.pcblist64 with sysctlnametomib() and passes a MIB
//  buffer size of zero. macOS 26 rejects that with ENOMEM, so Windows programs saw no
//  network connections at all. Steam checks which program owns each connection to its
//  local UI server and rejected its own browser, leaving an "Unexpected Transport Error".
//

#include <dlfcn.h>
#include <sys/sysctl.h>

typedef int (*NameToMibFunction)(const char *, int *, size_t *);
static NameToMibFunction realNameToMib;

__attribute__((constructor)) static void loadLibSystem(void) {
    realNameToMib = (NameToMibFunction)dlsym(dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY), "sysctlnametomib");
}

int sysctlnametomib(const char *name, int *mib, size_t *size) {
    if (size && *size == 0) *size = CTL_MAXNAME;
    return realNameToMib(name, mib, size);
}
