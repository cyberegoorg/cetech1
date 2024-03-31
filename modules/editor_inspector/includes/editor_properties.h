#pragma once

#include <cetech1/core/core.h>

typedef struct ct_editor_cdb_proprties_args
{
    const char *filter;
    uint32_t max_autopen_depth;
} ct_editor_cdb_proprties_args;

typedef struct ct_editor_ui_property_aspect
{
    void (*ui_property)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, uint32_t prop_idx, ct_editor_cdb_proprties_args args);
} ct_editor_ui_property_aspect;

typedef struct ct_editor_ui_properties_aspect
{
    void (*ui_properties)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, ct_editor_cdb_proprties_args args);
} ct_editor_ui_properties_aspect;
