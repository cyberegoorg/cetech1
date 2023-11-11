#pragma once
#include "types.h"
#include "cdb.h"
#include "faicons.h"

typedef struct ct_editorui_ui_i
{
    void (*ui)(struct ct_allocator_t *allocator);
} ct_editorui_ui_i;
