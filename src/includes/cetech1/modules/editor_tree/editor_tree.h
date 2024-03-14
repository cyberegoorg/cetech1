#pragma once

#include <cetech1/core/core.h>

typedef struct ct_editor_cdb_tree_result
{
    bool is_changed;
    bool is_prop;
    uint32_t prop_idx;
    ct_cdb_objid_t in_set_obj;
} ct_editor_cdb_tree_result;
typedef struct ct_editor_cdb_tree_args
{
    bool expand_object;
    ct_cdb_objid_t ignored_object;
    ct_strid32_t only_types;
    ct_cdb_objid_t opened_obj;
    const char *filter;
    bool multiselect;
    ct_editor_cdb_tree_result result;
} ct_editor_cdb_tree_args;

typedef struct ct_editor_ui_tree_aspect
{
    ct_cdb_objid_t (*ui_tree)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, ct_cdb_objid_t selected_obj, ct_editor_cdb_tree_args args);
    void (*ui_drop_obj)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, ct_cdb_objid_t drop_obj);
} ct_editor_ui_tree_aspect;
