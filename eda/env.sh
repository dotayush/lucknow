# source me. analog (magic/netgen/xschem/ngspice/cic*) and digital (librelane) share one sky130 pdk
export EDA=${EDA:-/media/ayush/secondary/eda}
PDK_ROOT=$(echo $EDA/pdk/ciel/sky130/versions/*/ | awk '{print $1}'); PDK_ROOT=${PDK_ROOT%/}   # no trailing slash: '//' starts a comment for ngspice < 40
export PDK_ROOT   # holds sky130A and sky130B, what aicex expects
export LIBRELANE_PDK_ROOT=$EDA/pdk                                          # ciel layout, for: librelane --pdk-root
export PDK=sky130B
export PATH=$EDA/tools/bin:$EDA/venv/bin:$EDA/oss_cad/bin:$PATH   # oss_cad ahead of /bin like in ~/.zshrc: verilator 5.039, not debian 5.032
export LD_LIBRARY_PATH=$EDA/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export AICEX=$EDA/src/aicex
# tools installed outside eda/: xschem and ngspice in /usr/local/bin, the riscv gcc. appended, so a shell that already has them is unchanged
for d in /usr/local/bin /opt/riscv32/bin; do case ":$PATH:" in *":$d:"*) ;; *) PATH=$PATH:$d;; esac; done
export PATH
