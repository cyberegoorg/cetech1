#pragma once

#include <cetech1/core/core.h>

typedef struct ct_editor_cdb_tree_args
{
    bool expand_object;
} ct_editor_cdb_tree_args;

typedef struct ct_editor_cdb_proprties_args
{

} ct_editor_cdb_proprties_args;

typedef struct ct_editorui_ui_property_aspect
{
    void (*ui_property)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, uint32_t prop_idx, ct_editor_cdb_proprties_args args);
} ct_editorui_ui_property_aspect;

typedef struct ct_editorui_ui_properties_aspect
{
    void (*ui_properties)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, ct_editor_cdb_proprties_args args);
} ct_editorui_ui_properties_aspect;

typedef struct ct_editorui_ui_tree_aspect
{
    ct_cdb_objid_t (*ui_tree)(struct ct_allocator_t *allocator, ct_cdb_db_t *db, ct_cdb_objid_t obj, ct_cdb_objid_t selected_obj, ct_editor_cdb_tree_args args);
} ct_editorui_ui_tree_aspect;

typedef struct ct_editorui_tab_o
{
} ct_editorui_tab_o;

typedef struct ct_editorui_tab_i
{
    struct ct_editorui_tab_type_i *vt;
    ct_editorui_tab_o *inst;
    uint32_t tabid;
    bool pinned_obj;
} ct_editorui_tab_i;

typedef struct ct_editorui_tab_type_i
{
    const char *tab_name;
    struct ct_strid32_t tab_hash;

    bool create_on_init;
    bool show_pin_object;
    bool show_sel_obj_in_title;

    const char *(*menu_name)(void);
    const char *(*title)(ct_editorui_tab_o *tab_inst);

    struct ct_editorui_tab_i *(*create)(ct_cdb_db_t *db);
    void (*destroy)(struct ct_editorui_tab_i *tab_i);

    void (*menu)(ct_editorui_tab_o *tab_inst);
    void (*ui)(ct_editorui_tab_o *tab_inst);
    void (*obj_selected)(ct_editorui_tab_o *tab_inst, ct_cdb_db_t *db, ct_cdb_objid_t obj);
    void (*focused)(ct_editorui_tab_o *tab_inst);
} ct_editorui_tab_type_i;
