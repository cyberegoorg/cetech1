#include <stdio.h>

#include <cetech1/core/log.h>

// TODO: how c varags to zig?

const ct_log_api_t *_logapi = NULL;
void _ct_log_set_log_api(const ct_log_api_t *logapi)
{
    _logapi = logapi;
}

void _ct_log_va(ct_log_level_e level, const char *scope, const char *format, va_list va)
{
    va_list cva;
    va_copy(cva, va);
    int len = vsnprintf(0, 0, format, cva);
    va_end(cva);

    char msg[len + 1];
    int s = vsnprintf(msg, CT_ARRAY_LEN(msg), format, va);

    _logapi->log(level, scope, msg);
}

void ct_log_info(const char *scope, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    _ct_log_va(CT_LOG_INFO, scope, format, args);
    va_end(args);
}

void ct_log_warn(const char *scope, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    _ct_log_va(CT_LOG_WARN, scope, format, args);
    va_end(args);
}

void ct_log_err(const char *scope, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    _ct_log_va(CT_LOG_ERR, scope, format, args);
    va_end(args);
}

void ct_log_debug(const char *scope, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    _ct_log_va(CT_LOG_DEBUG, scope, format, args);
    va_end(args);
}
