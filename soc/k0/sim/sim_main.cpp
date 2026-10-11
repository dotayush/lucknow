// verilator harness for the soc: loads a binary into ram, runs, decodes the uart transmit line to stdout
// and can type a file on the receive line. see build.sh. arguments:
//   +image=<file>[@<hex address>]   binary loaded into ram (repeatable), default address is the ram base
//   +rx=<file>                      bytes sent to the uart
//   +rx_delay=<clocks>              clocks before the first received byte (default 20000)
//   +rx_gap=<bit times>             idle time between received bytes (default 2). the uart has no fifo: give
//                                   the kernel's interrupt handler time, like a person typing
//   +max_cycles=<n>                 stop after n clocks (default 2e9)
//   +stop_on=<text>[|<text>...]     stop once the console printed one of the texts
//   +trace=<file>                   write the pc of every retired instruction (can be big)
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include "Vsoc.h"
#include "Vsoc___024root.h"
#include "verilated.h"

static const uint32_t RAM_BASE = 0x80000000u;

static std::string plusarg(int argc, char** argv, const char* key) {
  std::string k = std::string("+") + key + "=";
  for (int i = 1; i < argc; i++) if (strncmp(argv[i], k.c_str(), k.size()) == 0) return argv[i] + k.size();
  return "";
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vsoc* top = new Vsoc;
  auto* r = top->rootp;
  auto& ram = r->soc__DOT__bus_inst__DOT__ram_inst__DOT__mem;
  const size_t ram_words = sizeof(ram) / sizeof(uint32_t);

  uint64_t max_cycles = 2000000000ull;
  if (!plusarg(argc, argv, "max_cycles").empty()) max_cycles = strtoull(plusarg(argc, argv, "max_cycles").c_str(), 0, 0);
  const int cpb = CLKS_PER_BIT; // the same number the soc was built with, see build.sh
  uint64_t rx_delay = 20000;
  if (!plusarg(argc, argv, "rx_delay").empty()) rx_delay = strtoull(plusarg(argc, argv, "rx_delay").c_str(), 0, 0);
  int rx_gap = 2;
  if (!plusarg(argc, argv, "rx_gap").empty()) rx_gap = atoi(plusarg(argc, argv, "rx_gap").c_str());
  std::string stop_on = plusarg(argc, argv, "stop_on");
  std::string rx_file = plusarg(argc, argv, "rx");
  std::string trace_file = plusarg(argc, argv, "trace");

  // reset: the ram restores itself while rst_n is low, so the image goes in after it
  top->clk = 0; top->rst_n = 0; top->uart_rx = 1;
  for (int i = 0; i < 4; i++) { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
  top->clk = 0; top->rst_n = 1; top->eval();

  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], "+image=", 7) != 0) continue;
    std::string spec = argv[i] + 7;
    uint32_t base = RAM_BASE;
    size_t at = spec.find('@');
    if (at != std::string::npos) { base = strtoul(spec.c_str() + at + 1, 0, 16); spec = spec.substr(0, at); }
    FILE* f = fopen(spec.c_str(), "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", spec.c_str()); return 2; }
    uint32_t w, idx = (base - RAM_BASE) / 4, n = 0;
    uint8_t b[4];
    size_t got;
    while ((got = fread(b, 1, 4, f)) > 0) {
      memset(b + got, 0, 4 - got);
      w = b[0] | (b[1] << 8) | (b[2] << 16) | ((uint32_t)b[3] << 24);
      if (idx >= ram_words) { fprintf(stderr, "image does not fit in ram\n"); return 2; }
      ram[idx++] = w; n++;
    }
    fclose(f);
    fprintf(stderr, "[sim] %s: %u words at 0x%08x\n", spec.c_str(), n, base);
  }

  std::vector<uint8_t> rx_bytes;
  if (!rx_file.empty()) {
    FILE* f = fopen(rx_file.c_str(), "rb");
    if (f) { int c; while ((c = fgetc(f)) != EOF) rx_bytes.push_back((uint8_t)c); fclose(f); }
  }
  FILE* trace = trace_file.empty() ? nullptr : fopen(trace_file.c_str(), "w");

  // uart transmit decoder
  int tx_state = 0, tx_count = 0, tx_bit = 0; uint8_t tx_byte = 0;
  std::string console;
  // uart receive driver
  size_t rx_pos = 0; int rx_phase = -1, rx_clk = 0; uint8_t rx_cur = 0;

  uint64_t cycle = 0;
  uint64_t last_instret = 0;
  bool stop = false;
  while (!stop && cycle < max_cycles && !Verilated::gotFinish()) {
    top->clk = 1; top->eval();
    top->clk = 0; top->eval();
    cycle++;

    // tx: wait for the falling edge (start bit), sample every bit in its middle
    int tx = top->uart_tx;
    if (tx_state == 0) {
      if (!tx) { tx_state = 1; tx_count = 1; }
    } else {
      tx_count++;
      if (tx_state == 1 && tx_count == cpb / 2 + 1) { tx_state = 2; tx_count = 0; tx_bit = 0; tx_byte = 0; }
      else if (tx_state == 2 && tx_count == cpb) {
        tx_count = 0;
        if (tx_bit < 8) { tx_byte |= (tx ? 1 : 0) << tx_bit; tx_bit++; }
        else { // stop bit
          putchar(tx_byte); fflush(stdout);
          console.push_back((char)tx_byte);
          if (console.size() > 4096) console.erase(0, 2048);
          size_t from = 0;
          while (!stop && from <= stop_on.size() && !stop_on.empty()) {
            size_t bar = stop_on.find('|', from);
            std::string one = stop_on.substr(from, bar == std::string::npos ? std::string::npos : bar - from);
            if (!one.empty() && console.find(one) != std::string::npos) stop = true;
            if (bar == std::string::npos) break;
            from = bar + 1;
          }
          tx_state = 0;
        }
      }
    }

    // rx
    if (rx_phase < 0) {
      top->uart_rx = 1;
      if (rx_pos < rx_bytes.size() && cycle >= rx_delay) { rx_cur = rx_bytes[rx_pos++]; rx_phase = 0; rx_clk = 0; }
    } else {
      if (rx_phase == 0) top->uart_rx = 0;
      else if (rx_phase <= 8) top->uart_rx = (rx_cur >> (rx_phase - 1)) & 1;
      else top->uart_rx = 1;
      if (++rx_clk == cpb) {
        rx_clk = 0; rx_phase++;
        if (rx_phase > 9 + rx_gap) rx_phase = -1; // idle bit times between bytes
      }
    }

    if (trace) {
      uint64_t ir = (uint64_t)r->soc__DOT__core_inst__DOT__csrfile_inst__DOT__instret;
      if (ir != last_instret) { fprintf(trace, "%08x\n", r->soc__DOT__core_inst__DOT__pc); last_instret = ir; }
    }
  }
  uint64_t instret = (uint64_t)r->soc__DOT__core_inst__DOT__csrfile_inst__DOT__instret;
  fprintf(stderr, "\n[sim] %llu clocks, %llu instructions retired%s\n", (unsigned long long)cycle,
          (unsigned long long)instret, stop ? " (stop_on matched)" : (cycle >= max_cycles ? " (cycle limit)" : ""));
  if (trace) fclose(trace);
  delete top;
  return stop ? 0 : 1;
}
