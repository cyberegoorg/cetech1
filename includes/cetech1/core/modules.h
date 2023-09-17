#pragma once
#include "types.h"

typedef uint8_t(ct_module_fce_t)(
    const struct ct_apidb_api_t *api,
    const struct ct_allocator_t *allocator,
    uint8_t load,
    uint8_t reload);

typedef struct ct_module_desc_t
{
    const char *name;
    ct_module_fce_t *module_fce;
} ct_module_desc_t;

typedef struct ct_modules_api_t
{
} ct_modules_api_t;
