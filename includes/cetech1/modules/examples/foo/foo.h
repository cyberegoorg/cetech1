#pragma once

#include <cetech1/core/core.h>

typedef struct ct_foo_api_t
{
    float (*foo)(float arg1);
} ct_foo_api_t;
