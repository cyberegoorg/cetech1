#pragma once

#include <cetech1/core/core.h>

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
