NPROCS:=1
NPROCS:=$(shell grep -c ^processor /proc/cpuinfo)

gem5/build/RISCV/gem5.opt:
	cd gem5 && scons EXTRAS=../nvmain build/RISCV/gem5.opt -j $(NPROCS) PYTHON_CONFIG=/usr/bin/python3-config

gem5.opt: gem5/build/RISCV/gem5.opt

.PHONY: gem5.opt