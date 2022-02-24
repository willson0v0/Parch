NPROCS			:=1
NPROCS			:=$(shell grep -c ^processor /proc/cpuinfo)
MODE 			?= debug
OBJDUMP 		:= rust-objdump --arch-name=riscv64
OBJCOPY 		:= rust-objcopy --binary-architecture=riscv64
OUTPUT			:= output
GEM5_OPT		:= gem5/build/RISCV/gem5.opt
M5_TERM			:= gem5/util/term
LOG_LVL			?= verbose
FEATURES		?= log_$(LOG_LVL)


ifeq ($(MODE), debug)
KERNEL_ELF_OUT := kernel/target/riscv64gc-unknown-none-elf/debug/parch_kernel
else ifeq ($(MODE), release)
KERNEL_ELF_OUT := kernel/target/riscv64gc-unknown-none-elf/release/parch_kernel
endif

KERNEL_ELF := $(OUTPUT)/parch.elf
KERNEL_ASM := $(OUTPUT)/parch.asm
KERNEL_SYM := $(OUTPUT)/parch.sym
KERNEL_BIN := $(OUTPUT)/parch.bin
KERNEL_FS_BIN := $(OUTPUT)/parch_fs.bin
MK_PARCHFS := testbench/parchfs/parchfs
PARCH_ROOTFS := testbench/parchfs/rootfs

$(GEM5_OPT): $(shell find gem5/src -type f) $(shell find nvmain/src -type f) $(shell find nvmain/Simulators -type f)
	cd gem5 && scons EXTRAS=../nvmain build/RISCV/gem5.opt -j $(NPROCS) PYTHON_CONFIG=/usr/bin/python3-config

gem5.opt: $(GEM5_OPT)

kernel/target/riscv64gc-unknown-none-elf/debug/parch_kernel: $(shell find kernel/src -type f)
	cd kernel && cargo build --features "$(FEATURES)"

kernel/target/riscv64gc-unknown-none-elf/release/parch_kernel: $(shell find kernel/src -type f)
	cd kernel && cargo build --release --features "$(FEATURES)" 

$(KERNEL_ELF): $(KERNEL_ELF_OUT) | $(OUTPUT)
	cp $(KERNEL_ELF_OUT) $@

$(KERNEL_SYM): $(KERNEL_ELF)
	$(OBJDUMP) -t $(KERNEL_ELF) | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d'  | sort > $@

$(KERNEL_ASM): $(KERNEL_ELF)
	$(OBJDUMP) -S --triple=riscv64 $(KERNEL_ELF) > $@

$(KERNEL_BIN): $(KERNEL_ELF)
	@chronic $(OBJCOPY) $(KERNEL_ELF) -O binary $@

$(KERNEL_FS_BIN): $(KERNEL_BIN) $(KERNEL_SYM) $(PARCH_ROOTFS)
	./$(MK_PARCHFS) output/parch.bin output/parch.sym output/parch_fs.bin testbench/parchfs/rootfs

$(PARCH_ROOTFS):
	make -C testbench/parchfs all

kernel: $(KERNEL_ELF) $(KERNEL_SYM) $(KERNEL_ASM) $(KERNEL_BIN) $(KERNEL_FS_BIN)

$(OUTPUT):
	@mkdir $@

m5term: $(M5_TERM)

$(M5_TERM)/m5term: $(M5_TERM)/term.c $(M5_TERM)/Makefile
	make -c $(M5_TERM)
	chmod 0755 $(M5_TERM)/m5term

debug-qemu: kernel
	qemu-system-riscv64 -s -S -machine virt -m 4G -nographic -device loader,file=$(KERNEL_FS_BIN),addr=0x80000000,force-raw=on

run-qemu: kernel
	qemu-system-riscv64 -machine virt -m 4G -nographic -device loader,file=$(KERNEL_FS_BIN),addr=0x80000000,force-raw=on

run-gem5: gem5.opt m5term kernel
	tmux new-session -d \
		"$(GEM5_OPT) gem5/configs/example/riscv/fs_linux.py --kernel $(KERNEL_ELF) --cpu-type=AtomicSimpleCPU --mem-type=NVMainMemory --nvmain-config=nvmain/Config/PerfectMemory.config --mem-size 2048MiB" && \
		tmux split-window -h "sleep 3 && $(M5_TERM)/m5term localhost 3456" && \
		tmux -2 attach-session -d

env:
	cargo install cargo-binutils
	rustup component add llvm-tools-preview


clean:
	cd kernel && cargo clean
	rm -rf output

.PHONY: gem5.opt run-gem5 clean kernel debug-qemu run-qemu m5term $(PARCH_ROOTFS) env