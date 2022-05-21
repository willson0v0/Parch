NPROCS			:=1
NPROCS			:=$(shell grep -c ^processor /proc/cpuinfo)
MODE 			?= debug
OBJDUMP 		:= rust-objdump --arch-name=riscv64
OBJCOPY 		:= rust-objcopy --binary-architecture=riscv64
OUTPUT			:= output
GEM5_OPT		:= gem5/build/RISCV/gem5.opt
M5_TERM			:= gem5/util/term
LOG_LVL			?= debug
FEATURES		?= log_$(LOG_LVL)
CPUS			:= 4
QEMU			:= ../env_clean/qemu/build/qemu-system-riscv64

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
QEMU_DTB   := $(OUTPUT)/qemu.dtb
QEMU_DTB_DUMP := $(OUTPUT)/qemu.dtb.dump
MK_PARCHFS := testbench/parchfs/parchfs

$(GEM5_OPT): $(shell find gem5/src -type f) $(shell find nvmain/src -type f) $(shell find nvmain/Simulators -type f)
	cd gem5 && scons EXTRAS=../nvmain build/RISCV/gem5.opt -j $(NPROCS) PYTHON_CONFIG=/usr/bin/python3-config

gem5.opt: $(GEM5_OPT)

kernel/target/riscv64gc-unknown-none-elf/debug/parch_kernel: $(shell find kernel/src -type f) $(QEMU_DTB)
	cd kernel && cargo build --features "$(FEATURES)" --target-dir=./target --no-default-features 

kernel/target/riscv64gc-unknown-none-elf/release/parch_kernel: $(shell find kernel/src -type f) $(QEMU_DTB)
	cd kernel && cargo build --release --features "$(FEATURES)" --target-dir=./target --no-default-features 

$(KERNEL_ELF): $(KERNEL_ELF_OUT) | $(OUTPUT)
	cp $(KERNEL_ELF_OUT) $@

$(KERNEL_SYM): $(KERNEL_ELF)
	$(OBJDUMP) -t $(KERNEL_ELF) | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d'  | sort > $@

$(KERNEL_ASM): $(KERNEL_ELF)
	$(OBJDUMP) -S --triple=riscv64 $(KERNEL_ELF) > $@

$(KERNEL_BIN): $(KERNEL_ELF)
	@chronic $(OBJCOPY) $(KERNEL_ELF) -O binary $@

$(KERNEL_FS_BIN): $(KERNEL_BIN) $(KERNEL_SYM) testbench
	./$(MK_PARCHFS) output/parch.bin output/parch.sym output/parch_fs.bin testbench/root_fs_parch

$(QEMU_DTB): $(OUTPUT)
	$(QEMU) -machine virt,dumpdtb=$(QEMU_DTB) -m 4G -nographic -device loader,file=$(KERNEL_FS_BIN),addr=0x80000000,force-raw=on -smp $(CPUS)

$(QEMU_DTB_DUMP): output/qemu.dtb
	dtc output/qemu.dtb > $(QEMU_DTB_DUMP)

testbench:
	make -C testbench all

kernel: $(KERNEL_ELF) $(KERNEL_SYM) $(KERNEL_ASM) $(KERNEL_BIN) $(KERNEL_FS_BIN) $(QEMU_DTB_DUMP)

$(OUTPUT):
	@mkdir $@

m5term: $(M5_TERM)

$(M5_TERM)/m5term: $(M5_TERM)/term.c $(M5_TERM)/Makefile
	make -c $(M5_TERM)
	chmod 0755 $(M5_TERM)/m5term

debug-qemu: kernel
	$(QEMU) -s -S -machine virt -d cpu_reset -D output/qemu.log -m 4G -nographic -device loader,file=$(KERNEL_FS_BIN),addr=0x80000000,force-raw=on -smp $(CPUS)

run-qemu: kernel
	$(QEMU) -machine virt -d cpu_reset -D output/qemu.log -m 4G -nographic -device loader,file=$(KERNEL_FS_BIN),addr=0x80000000,force-raw=on -smp $(CPUS)

# TODO: change to --param 'system.workload.extras = "$(KERNEL_FS_BIN)"' --param 'system.workload.extras_addrs = 0x80000000', no more elf
run-gem5: gem5.opt m5term kernel
	tmux new-session -d \
		"$(GEM5_OPT) gem5/configs/example/riscv/fs_linux.py --kernel $(KERNEL_ELF) --cpu-type=AtomicSimpleCPU --mem-type=NVMainMemory --nvmain-config=nvmain/Config/PerfectMemory.config --mem-size 4096MiB" && \
		tmux split-window -h "sleep 3 && $(M5_TERM)/m5term localhost 3456" && \
		tmux -2 attach-session -d

env:
	cargo install cargo-binutils
	rustup component add llvm-tools-preview

dtb: output/qemu.dtb.dump

clean:
	cd kernel && cargo clean
	rm -rf output
	make -C testbench clean

.PHONY: gem5.opt run-gem5 clean kernel debug-qemu run-qemu m5term env testbench dtb