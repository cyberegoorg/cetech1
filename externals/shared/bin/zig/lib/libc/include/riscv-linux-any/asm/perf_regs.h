/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/* Copyright (C) 2019 Hangzhou C-SKY Microsystems co.,ltd. */

#ifndef _ASM_RISCV_PERF_REGS_H
#define _ASM_RISCV_PERF_REGS_H

enum perf_event_riscv_regs {
	PERF_REG_RISCV_PC,
	PERF_REG_RISCV_RA,
	PERF_REG_RISCV_SP,
	PERF_REG_RISCV_GP,
	PERF_REG_RISCV_TP,
	PERF_REG_RISCV_T0,
	PERF_REG_RISCV_T1,
	PERF_REG_RISCV_T2,
	PERF_REG_RISCV_S0,
	PERF_REG_RISCV_S1,
	PERF_REG_RISCV_A0,
	PERF_REG_RISCV_A1,
	PERF_REG_RISCV_A2,
	PERF_REG_RISCV_A3,
	PERF_REG_RISCV_A4,
	PERF_REG_RISCV_A5,
	PERF_REG_RISCV_A6,
	PERF_REG_RISCV_A7,
	PERF_REG_RISCV_S2,
	PERF_REG_RISCV_S3,
	PERF_REG_RISCV_S4,
	PERF_REG_RISCV_S5,
	PERF_REG_RISCV_S6,
	PERF_REG_RISCV_S7,
	PERF_REG_RISCV_S8,
	PERF_REG_RISCV_S9,
	PERF_REG_RISCV_S10,
	PERF_REG_RISCV_S11,
	PERF_REG_RISCV_T3,
	PERF_REG_RISCV_T4,
	PERF_REG_RISCV_T5,
	PERF_REG_RISCV_T6,
	PERF_REG_RISCV_MAX,
};
#endif /* _ASM_RISCV_PERF_REGS_H */