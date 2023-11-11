#include <cetech1/core/core.h>
#include <cetech1/modules/examples/foo/foo.h>

#define MODULE_NAME "bar"

static ct_foo_api_t *_foo_api = NULL;
static ct_log_api_t *_log = NULL;
static ct_strid_api_t *_strid = NULL;

static bool spam_log = false;

// Global state that can surive hot-reload
typedef struct G
{
    uint32_t var1;
} G;
static G *_g = NULL;

static void kernel_task_init()
{
    return;
}

static void kernel_task_shutdown()
{
    return;
}

static void kernel_task_update1(ct_allocator_t *frame_allocator, ct_cdb_db_t *main_db, uint64_t kernel_tick, float dt)
{
    float a = _foo_api->foo(42);
    if (spam_log)
    {
        _log->info(MODULE_NAME, "_foo_api->foo(42) => %f", a);
        _log->info(MODULE_NAME, "_g.var1 => %d", _g->var1);
    }
    ++_g->var1;

    return;
}

static ct_kernel_task_i kernel_task = {
    .name = MODULE_NAME "KernelTask",
    .depends = 0,
    .depends_n = 0,
    .init = kernel_task_init,
    .shutdown = kernel_task_shutdown,
};

static ct_kernel_task_update_i update_task = {
    .name = "BarUpdate",
    .depends = 0,
    .depends_n = 0,
    .update = kernel_task_update1,
};

CT_DECL_MODULE(bar, "Simple module in C")
(const ct_apidb_api_t *apidb, const ct_allocator_t *allocator, bool load, bool reload)
{
    _log = apidb->get_api(CT_APIDB_LANG_C, ct_apidb_api_arg(ct_log_api_t));
    _strid = apidb->get_api(CT_APIDB_LANG_C, ct_apidb_api_arg(ct_strid_api_t));
    _foo_api = apidb->get_api(CT_APIDB_LANG_C, ct_apidb_api_arg(ct_foo_api_t));

    _g = (G *)apidb->global_var(MODULE_NAME, "_g", sizeof(G), &(G){});

    update_task.phase = _strid->strid64(CT_KERNEL_PHASE_ONUPDATE);

    // apidb->impl_or_remove(ct_apidb_name(ct_kernel_task_i), &kernel_task, load);
    // apidb->impl_or_remove(ct_apidb_name(ct_kernel_task_update_i), &update_task, load);

    return 1;
}
