// hpmstat: prints the hardware performance counters of the core, or the change over a command.
//   hpmstat                  the counts since reset
//   hpmstat <command> ...    runs the command and prints what it cost
// the counters are the core's, not the process's: everything that ran in between counts, the kernel and
// other processes included. user mode can read them because mcounteren allows it (CHIP.md).
// counters 3..10 count the events selected at reset: load, store, branch taken, branch not taken, jump,
// exception, interrupt, instruction fetch wait clock.
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define RD64(lo, hi) ({                                                            \
    unsigned h1, h2, l;                                                            \
    do {                                                                           \
      __asm__ volatile("csrr %0, " #hi : "=r"(h1));                                \
      __asm__ volatile("csrr %0, " #lo : "=r"(l));                                 \
      __asm__ volatile("csrr %0, " #hi : "=r"(h2));                                \
    } while (h1 != h2);                                                            \
    ((unsigned long long)h1 << 32) | l; })

#define N 10
static const char *names[N] = {"cycles", "instructions", "loads", "stores", "branches taken",
                               "branches not taken", "jumps", "exceptions", "interrupts", "fetch wait clocks"};

static void read_all(unsigned long long v[N]) {
  v[0] = RD64(0xC00, 0xC80);
  v[1] = RD64(0xC02, 0xC82);
  v[2] = RD64(0xC03, 0xC83);
  v[3] = RD64(0xC04, 0xC84);
  v[4] = RD64(0xC05, 0xC85);
  v[5] = RD64(0xC06, 0xC86);
  v[6] = RD64(0xC07, 0xC87);
  v[7] = RD64(0xC08, 0xC88);
  v[8] = RD64(0xC09, 0xC89);
  v[9] = RD64(0xC0A, 0xC8A);
}

static void no_counters(int sig) {
  static const char msg[] = "hpmstat: this machine does not let user mode read the counters (it is not k0?)\n";
  (void)sig;
  write(2, msg, sizeof msg - 1);
  _exit(2);
}

int main(int argc, char **argv) {
  signal(SIGILL, no_counters); // QEMU and most cores reset mcounteren to 0
  unsigned long long a[N], b[N];
  int status = 0;
  read_all(a);
  if (argc > 1) {
    pid_t pid = vfork();
    if (pid == 0) {
      execvp(argv[1], argv + 1);
      _exit(127);
    }
    waitpid(pid, &status, 0);
    read_all(b);
    for (int i = 0; i < N; i++) b[i] -= a[i];
  } else {
    memcpy(b, a, sizeof b);
  }
  for (int i = 0; i < N; i++) printf("%-20s %llu\n", names[i], b[i]);
  if (b[1]) printf("%-20s %llu.%02llu\n", "cycles/instruction", b[0] / b[1], (b[0] * 100 / b[1]) % 100);
  return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
