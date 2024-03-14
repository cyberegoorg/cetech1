#pragma once
#include "types.h"

typedef struct ct_strid_api_t
{
    ct_strid32_t (*strid32)(const char *str);
    ct_strid64_t (*strid64)(const char *str);
} ct_strid_api_t;
