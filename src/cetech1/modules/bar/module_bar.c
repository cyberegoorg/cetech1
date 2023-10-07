#include <cetech1/core/core.h>
#include <cetech1/modules/foo/foo.h>

#define MODULE_NAME "bar"

ct_foo_api_t *_foo_api = NULL;
ct_log_api_t *_log = NULL;
ct_strid_api_t *_strid = NULL;

typedef struct G
{
    uint32_t var1;
} G;
G *_g = NULL;

void kernel_task_init()
{
    return;
}

void kernel_task_shutdown()
{
    return;
}

void kernel_task_update1(ct_allocator_t *frame_allocator, ct_cdb_db_t *main_db, uint64_t kernel_tick, float dt)
{
    float a = _foo_api->foo(42);
    _log->info(MODULE_NAME, "_foo_api->foo(42) => %f", a);

    _log->info(MODULE_NAME, "_g.var1 => %d", _g->var1);
    ++_g->var1;

    return;
}

ct_kernel_task_i kernel_task = {
    .name = MODULE_NAME "KernelTask",
    .depends = 0,
    .depends_n = 0,
    .init = kernel_task_init,
    .shutdown = kernel_task_shutdown,
};

ct_kernel_task_update_i _update1 = {};

CT_DECL_MODULE(bar, "Simple module in C")
(const ct_apidb_api_t *apidb, const ct_allocator_t *allocator, uint8_t load, uint8_t reload)
{
    _log = apidb->get_api(CT_APIDB_LANG_C, ct_apidb_api_arg(ct_log_api_t));
    _strid = apidb->get_api(CT_APIDB_LANG_C, ct_apidb_api_arg(ct_strid_api_t));
    _foo_api = apidb->get_api(CT_APIDB_LANG_C, ct_apidb_api_arg(ct_foo_api_t));

    _g = (G *)apidb->global_var(MODULE_NAME, "_g", sizeof(G));
    if (load && !reload)
    {
        *_g = (G){};
    }

    _update1 = (ct_kernel_task_update_i){
        .phase = _strid->strid64(CT_KERNEL_PHASE_ONUPDATE),
        .name = "BarUpdate",
        .depends = 0,
        .depends_n = 0,
        .update = kernel_task_update1,
    };

    apidb->impl_or_remove(ct_apidb_name(ct_kernel_task_i), &kernel_task, load);
    apidb->impl_or_remove(ct_apidb_name(ct_kernel_task_update_i), &_update1, load);

    return 1;
}
