#pragma once

#include "types.h"

typedef enum ct_log_level_e
{
      CT_LOG_ERR,
      CT_LOG_WARN,
      CT_LOG_INFO,
      CT_LOG_DEBUG
} ct_log_level_e;

typedef struct ct_log_api_t
{
      void (*log)(ct_log_level_e level, const char *scope, const char *log_line);
      void (*info)(const char *scope, const char *fmt, ...) CT_ATTR_FORMAT(2, 3);
      void (*debug)(const char *scope, const char *fmt, ...) CT_ATTR_FORMAT(2, 3);
      void (*warn)(const char *scope, const char *fmt, ...) CT_ATTR_FORMAT(2, 3);
      void (*err)(const char *scope, const char *fmt, ...) CT_ATTR_FORMAT(2, 3);
} ct_log_api_t;
