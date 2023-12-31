#pragma once

#include <cetech1/core/core.h>

typedef struct ct_editor_cdb_tree_args
{
    bool expand_object;
    ct_cdb_objid_t ignored_object;
    ct_strid32_t only_types;
    const char *filter;
    bool multiselect;
} ct_editor_cdb_tree_args;

typedef struct ct_editorui_ui_tree_aspect
{
    ct_cdb_objid_t (*ui_tree)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, ct_cdb_objid_t selected_obj, ct_editor_cdb_tree_args args);
} ct_editorui_ui_tree_aspect;
