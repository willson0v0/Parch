NPROCS			:=1
NPROCS			:=$(shell grep -c ^processor /proc/cpuinfo)
MODE 			?= debug
OBJDUMP 		:= rust-objdump --arch-name=riscv64
OBJCOPY 		:= rust-objcopy --binary-architecture=riscv64
OUTPUT			:= output
GEM5_OPT		:= gem5/build/RISCV/gem5.opt

ifeq ($(MODE), debug)
KERNEL_ELF_OUT := kernel/target/riscv64gc-unknown-none-elf/debug/parch_kernel
else ifeq ($(MODE), release)
KERNEL_ELF_OUT := kernel/target/riscv64gc-unknown-none-elf/release/parch_kernel
endif

KERNEL_ELF := $(OUTPUT)/parch.elf
KERNEL_ASM := $(OUTPUT)/parch.asm
KERNEL_SYM := $(OUTPUT)/parch.sym
KERNEL_BIN := $(OUTPUT)/parch.bin

$(GEM5_OPT):
	cd gem5 && scons EXTRAS=../nvmain build/RISCV/gem5.opt -j $(NPROCS) PYTHON_CONFIG=/usr/bin/python3-config

gem5.opt: $(GEM5_OPT)

kernel/target/riscv64gc-unknown-none-elf/debug/parch_kernel: $(shell find kernel/src -type f)
	cd kernel && cargo build

kernel/target/riscv64gc-unknown-none-elf/release/parch_kernel: $(shell find kernel/src -type f)
	cd kernel && cargo build --release

$(KERNEL_ELF): $(KERNEL_ELF_OUT) | $(OUTPUT)
	cp $(KERNEL_ELF_OUT) $@

$(KERNEL_SYM): $(KERNEL_ELF)
	chronic $(OBJDUMP) -t $(KERNEL_ELF) | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d'  | sort > $@

$(KERNEL_ASM): $(KERNEL_ELF)
	$(OBJDUMP) -S --triple=riscv64 $(KERNEL_ELF) > $@

$(KERNEL_BIN): $(KERNEL_ELF)
	chronic $(OBJCOPY) $(KERNEL_ELF) --strip-all -O binary $@

kernel: $(KERNEL_ELF) $(KERNEL_SYM) $(KERNEL_ASM) $(KERNEL_BIN)

$(OUTPUT):
	mkdir $@

debug-qemu: kernel
	qemu-system-riscv64 -s -S -machine virt -nographic -bios $(KERNEL_BIN)

run-qemu: kernel
	qemu-system-riscv64 -machine virt -nographic -bios $(KERNEL_BIN)

run-gem5: gem5.opt
	$(GEM5_OPT) gem5/configs/example/riscv/fs_linux.py --kernel $(KERNEL_ELF) --cpu-type=AtomicSimpleCPU

clean:
	cd kernel && cargo clean
	rm -rf output

.PHONY: gem5.opt run-gem5 clean kernel debug-qemu run-qemu