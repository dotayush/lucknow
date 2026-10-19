# path segments of the k0 core (module control) for core/l0/librelane/screen.sh: SCREEN_SEGS=this file.
# seg, R (clock pins) and D (data pins) come from screen.sh.
set A {mem_addr* mem_data_out* mem_access_type* mem_read mem_write}
seg "pc -> imem_addr" $R [get_ports imem_addr*]
seg "imem_data -> mem_addr/ctl/wdata" [get_ports imem_data*] [get_ports $A]
seg "imem_data -> flops" [get_ports imem_data*] $D
seg "mem_data_in -> flops" [get_ports mem_data_in*] $D
seg "mem_error -> flops" [get_ports mem_error*] $D
seg "mem_ready -> flops" [get_ports mem_ready] $D
seg "imem_ready -> flops" [get_ports imem_ready] $D
seg "imem_ready -> mem_read/write" [get_ports imem_ready] [get_ports {mem_read mem_write}]
seg "irq/time -> flops" [get_ports {irq_* time_value*}] $D
seg "flops -> mem_addr/ctl/wdata" $R [get_ports $A]
seg "flops -> flops" $R $D
