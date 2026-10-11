// a tiny init and shell for the nommu kernel, freestanding (no libc), position independent so it
// needs no relocations. packed into a bflt file by mkflat.py.
typedef unsigned int u32;

static long sys(long n, long a, long b, long c) {
  register long a0 __asm__("a0") = a;
  register long a1 __asm__("a1") = b;
  register long a2 __asm__("a2") = c;
  register long a7 __asm__("a7") = n;
  __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
  return a0;
}

enum { SYS_READ = 63, SYS_WRITE = 64, SYS_EXIT = 93, SYS_SYSINFO = 179, SYS_GETPID = 172 };

static int len(const char* s) { int n = 0; while (s[n]) n++; return n; }
static void puts_(const char* s) { sys(SYS_WRITE, 1, (long)s, len(s)); }
static void putu(u32 v) {
  char b[12]; int i = 11; b[i] = 0;
  do { b[--i] = '0' + v % 10; v /= 10; } while (v);
  puts_(b + i);
}
static int eq(const char* a, const char* b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static u32 atou(const char* s) { u32 v = 0; while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0'); return v; }

// matches struct sysinfo of rv32 (time_t is 32 bit here): only the first fields are used
struct sysinfo_t { long uptime; unsigned long loads[3]; unsigned long totalram, freeram, sharedram, bufferram,
                   totalswap, freeswap; unsigned short procs, pad; unsigned long totalhigh, freehigh; unsigned int mem_unit;
                   char f[20]; };

static void cmd(char* line) {
  char* arg = line;
  while (*arg && *arg != ' ') arg++;
  if (*arg) { *arg++ = 0; while (*arg == ' ') arg++; }
  if (eq(line, "")) return;
  if (eq(line, "help")) {
    puts_("echo <text>  uptime  mem  pid  fib <n>  mul <a> <b>  div <a> <b>  exit\n");
  } else if (eq(line, "echo")) {
    puts_(arg); puts_("\n");
  } else if (eq(line, "uptime")) {
    struct sysinfo_t si; sys(SYS_SYSINFO, (long)&si, 0, 0);
    putu(si.uptime); puts_(" s\n");
  } else if (eq(line, "mem")) {
    struct sysinfo_t si; sys(SYS_SYSINFO, (long)&si, 0, 0);
    putu(si.freeram * si.mem_unit / 1024); puts_(" KiB free of "); putu(si.totalram * si.mem_unit / 1024); puts_(" KiB\n");
  } else if (eq(line, "pid")) {
    putu(sys(SYS_GETPID, 0, 0, 0)); puts_("\n");
  } else if (eq(line, "fib")) {
    u32 a = 0, b = 1, n = atou(arg);
    while (n--) { u32 t = a + b; a = b; b = t; }
    putu(a); puts_("\n");
  } else if (eq(line, "mul") || eq(line, "div")) {
    u32 x = atou(arg);
    const char* p = arg; while (*p && *p != ' ') p++; while (*p == ' ') p++;
    u32 y = atou(p);
    if (line[0] == 'm') putu(x * y); else if (y) putu(x / y); else puts_("divide by zero");
    puts_("\n");
  } else if (eq(line, "exit")) {
    sys(SYS_EXIT, 0, 0, 0);
  } else {
    puts_("unknown command: "); puts_(line); puts_("\n");
  }
}

void __attribute__((section(".text.start"))) _start(void) {
  char line[96];
  int n = 0;
  puts_("\nlucknow k0: init is running in user space\n");
  for (;;) {
    n = 0;
    puts_("k0# ");
    for (;;) {
      char c;
      if (sys(SYS_READ, 0, (long)&c, 1) != 1) continue;
      if (c == '\r' || c == '\n') { puts_("\n"); break; } // the tty echoes input itself
      if (n < (int)sizeof(line) - 1) line[n++] = c;
    }
    line[n] = 0;
    cmd(line);
  }
}
