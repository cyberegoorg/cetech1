#pragma once
#include "types.h"
#include "cdb.h"
#include "faicons.h"

typedef struct ct_editorui_ui_i
{
    void (*ui)(struct ct_allocator_t *allocator);
} ct_editorui_ui_i;

typedef struct ct_editorui_ui_tree_aspect
{
    ct_cdb_objid_t (*ui_tree)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, ct_cdb_objid_t selected_obj, bool recursive);
} ct_editorui_ui_tree_aspect;

typedef struct ct_editorui_ui_properties_aspect
{
    void (*ui_properties)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj);
} ct_editorui_ui_properties_aspect;

typedef struct ct_editorui_ui_property_aspect
{
    void (*ui_property)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, uint32_t prop_idx);
} ct_editorui_ui_property_aspect;
