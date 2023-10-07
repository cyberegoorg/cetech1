#pragma once
#include "types.h"
#include "cdb.h"

#define CT_KERNEL_PHASE_ONLOAD "OnLoad"
#define CT_KERNEL_PHASE_POSTLOAD "PostLoad"
#define CT_KERNEL_PHASE_PREUPDATE "PreUpdate"
#define CT_KERNEL_PHASE_ONUPDATE "OnUpdate"
#define CT_KERNEL_PHASE_ONVALIDATE "OnValidate"
#define CT_KERNEL_PHASE_POSTUPDATE "PostUpdate"
#define CT_KERNEL_PHASE_PRESTORE "PreStore"
#define CT_KERNEL_PHASE_ONSTORE "OnStore"

typedef struct ct_kernel_task_update_i
{
      ct_strid64_t phase;
      const char *name;
      const ct_strid64_t *depends;
      uint64_t depends_n;
      void (*update)(ct_allocator_t *frame_allocator, ct_cdb_db_t *main_db, uint64_t kernel_tick, float dt);
} ct_kernel_task_update_i;

typedef struct ct_kernel_task_i
{
      const char *name;
      const ct_strid64_t *depends;
      uint64_t depends_n;

      void (*init)(ct_cdb_db_t *main_db);
      void (*shutdown)(void);
} ct_kernel_task_i;
