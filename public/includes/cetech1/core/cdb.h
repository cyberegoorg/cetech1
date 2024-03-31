#pragma once
#include "types.h"

typedef struct ct_cdb_type_idx_t
{
    uint32_t idx;
} ct_cdb_type_idx_t;

typedef struct ct_cdb_objid_t
{
    uint32_t id;
    ct_cdb_type_idx_t type_idx;
} ct_cdb_objid_t;

#define CT_CDB_OBJID_ZERO ((ct_cdb_objid_t){.id = 0, .type_idx = (ct_cdb_type_idx_t){0}})

typedef struct ct_cdb_obj_o
{
} ct_cdb_obj_o;

typedef struct ct_cdb_db_t
{
} ct_cdb_db_t;

typedef struct ct_cdb_create_types_i
{
    void (*create_types)(struct ct_cdb_db_t *db);
} ct_cdb_create_types_i;

typedef enum ct_cdb_type_e
{
    CT_CDB_TYPE_NONE = 0,
    CT_CDB_TYPE_BOOL = 1,
    CT_CDB_TYPE_U64 = 2,
    CT_CDB_TYPE_I64 = 3,
    CT_CDB_TYPE_U32 = 4,
    CT_CDB_TYPE_I32 = 5,
    CT_CDB_TYPE_F32 = 6,
    CT_CDB_TYPE_F64 = 7,
    CT_CDB_TYPE_STR = 8,
    CT_CDB_TYPE_BLOB = 9,
    CT_CDB_TYPE_SUBOBJECT = 10,
    CT_CDB_TYPE_REFERENCE = 11,
    CT_CDB_TYPE_SUBOBJECT_SET = 12,
    CT_CDB_TYPE_REFERENCE_SET = 13,
} ct_cdb_type_e;

// Object property definition
typedef struct ct_cdb_prop_def_t
{
    // Property idx
    uint32_t prop_idx;

    // Property name
    const char *name;

    // Property type
    ct_cdb_type_e type;

    // Force type_hash for ref/subobj base types
    ct_strid32_t type_hash;

} ct_cdb_prop_def_t;

typedef struct ct_cdb_type_def_t
{
    const ct_cdb_prop_def_t *props;
    uint32_t n;
} ct_cdb_type_def_t;

typedef struct ct_cdb_api_t
{
} ct_cdb_api_t;
