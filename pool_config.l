/* -*-pgsql-c-*- */
/*
 *
 * $Header: /cvsroot/pgpool/pgpool-II/pool_config.l,v 1.28 2009/12/06 08:46:34 t-ishii Exp $
 *
 * pgpool: a language independent connection pool server for PostgreSQL 
 * written by Tatsuo Ishii
 *
 * Copyright (c) 2003-2009	PgPool Global Development Group
 *
 * Permission to use, copy, modify, and distribute this software and
 * its documentation for any purpose and without fee is hereby
 * granted, provided that the above copyright notice appear in all
 * copies and that both that copyright notice and this permission
 * notice appear in supporting documentation, and that the name of the
 * author not be used in advertising or publicity pertaining to
 * distribution of the software without specific, written prior
 * permission. The author makes no representations about the
 * suitability of this software for any purpose.  It is provided "as
 * is" without express or implied warranty.
 *
 * pool_config.l: read configuration file
 *
 */

%{

#include "pool.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK_CONTEXT(mask, context) ((mask) & (context))

/* to shut off compiler warnings */
int yylex(void);

POOL_CONFIG *pool_config;	/* configuration values */
POOL_SYSTEMDB_CONNECTION_POOL *system_db_info;
static unsigned Lineno;
static char *default_reset_query_list[] = {"ABORT", "DISCARD ALL"};

typedef enum {
  POOL_KEY = 1,
  POOL_INTEGER,
  POOL_REAL,
  POOL_STRING,
  POOL_UNQUOTED_STRING,
  POOL_EQUALS,
  POOL_EOL,
  POOL_PARSE_ERROR
} POOL_TOKEN;

static char *extract_string(char *value, POOL_TOKEN token);
static char **extract_string_tokens(char *str, char *delim, int *n);
static int eval_logical(char *str);
static void clear_host_entry(int slot);

%}

%option 8bit
%option never-interactive
%option nounput
%option noyywrap

SIGN            ("-"|"+")
DIGIT           [0-9]
HEXDIGIT        [0-9a-fA-F]

INTEGER         {SIGN}?({DIGIT}+|0x{HEXDIGIT}+)

EXPONENT        [Ee]{SIGN}?{DIGIT}+
REAL            {SIGN}?{DIGIT}*"."{DIGIT}*{EXPONENT}?

LETTER          [A-Za-z_\200-\377]
LETTER_OR_DIGIT [A-Za-z_0-9\200-\377]

KEY              {LETTER}{LETTER_OR_DIGIT}*

UNQUOTED_STRING {LETTER}({LETTER_OR_DIGIT}|[-._:/])*
STRING          \'([^'\n]|\\.)*\'

%%

\n              Lineno++; return POOL_EOL;
[ \t\r]+        /* eat whitespace */
#.*$            /* eat comment */

{KEY}           return POOL_KEY;
{STRING}        return POOL_STRING;
{UNQUOTED_STRING} return POOL_UNQUOTED_STRING;
{INTEGER}       return POOL_INTEGER;
{REAL}          return POOL_REAL;
=               return POOL_EQUALS;

.               return POOL_PARSE_ERROR;

%%

int pool_init_config(void)
{
	int res;
	static char localhostname[256];
	int i;

	pool_config = malloc(sizeof(POOL_CONFIG));
	if (pool_config == NULL)
	{
		pool_error("failed to allocate pool_config");
		return(-1);
	}

	memset(pool_config, 0, sizeof(POOL_CONFIG));

	pool_config->backend_desc = pool_shared_memory_create(sizeof(BackendDesc));
	if (pool_config->backend_desc == NULL)
	{
		pool_error("failed to allocate pool_config->backend_desc");
		return -1;
	}

	/* set hardcoded default values */
	pool_config->listen_addresses = "localhost";
	pool_config->port = 9999;
	pool_config->pcp_port = 9898;
	pool_config->socket_dir = DEFAULT_SOCKET_DIR;
	pool_config->pcp_socket_dir = DEFAULT_SOCKET_DIR;
	pool_config->backend_socket_dir = DEFAULT_SOCKET_DIR;
	pool_config->pcp_timeout = 10;
	pool_config->num_init_children = 32;
	pool_config->max_pool = 4;
	pool_config->child_life_time = 300;
	pool_config->client_idle_limit = 0;
	pool_config->connection_life_time = 0;
	pool_config->child_max_connections = 0;
	pool_config->authentication_timeout = 60;
	pool_config->logdir = DEFAULT_LOGDIR;
	pool_config->pid_file_name = DEFAULT_PID_FILE_NAME;
 	pool_config->log_statement = 0;
 	pool_config->log_per_node_statement = 0;
	pool_config->log_connections = 0;
	pool_config->log_hostname = 0;
	pool_config->enable_pool_hba = 0;

	pool_config->replication_mode = 0;
	pool_config->load_balance_mode = 0;
	pool_config->replication_stop_on_mismatch = 0;
	pool_config->replicate_select = 0;
	pool_config->reset_query_list = default_reset_query_list;
	pool_config->num_reset_queries = sizeof(default_reset_query_list)/sizeof(char *);
	pool_config->reset_query_list = default_reset_query_list;
	pool_config->print_timestamp = 1;
	pool_config->master_slave_mode = 0;
	pool_config->connection_cache = 1;
	pool_config->health_check_timeout = 20;
	pool_config->health_check_period = 0;
	pool_config->health_check_user = "nobody";
	pool_config->failover_command = "";
	pool_config->failback_command = "";
	pool_config->fail_over_on_backend_error = 1;
	pool_config->insert_lock = 1;
	pool_config->ignore_leading_white_space = 1;
	pool_config->parallel_mode = 0;
	pool_config->enable_query_cache = 0;
	pool_config->system_db_hostname = "localhost";
	pool_config->system_db_port = 5432;
	pool_config->system_db_dbname = "pgpool";
	pool_config->system_db_schema = "pgpool_catalog";
	pool_config->system_db_user = "pgpool";
	pool_config->system_db_password = "";
	pool_config->backend_desc->num_backends = 0;
    pool_config->recovery_user = "";
    pool_config->recovery_password = "";
    pool_config->recovery_1st_stage_command = "";
    pool_config->recovery_2nd_stage_command = "";
	pool_config->recovery_timeout = 90;
	pool_config->client_idle_limit_in_recovery = 0;

	res = gethostname(localhostname,sizeof(localhostname));
	if(res !=0 )
	{
		pool_debug("faild to get this hostname");
	}
	pool_config->pgpool2_hostname = localhostname;

	for (i=0;i<MAX_CONNECTION_SLOTS;i++)
	{
		clear_host_entry(i);
	}
	return 0;
}

int pool_get_config(char *confpath, POOL_CONFIG_CONTEXT context)
{
	FILE *fd;
	int token;
	char key[1024];
	double total_weight;
	int i;

#define PARSE_ERROR()		pool_error("pool_config: parse error at line %d '%s'", Lineno, yytext)

	/* open config file */
	fd = fopen(confpath, "r");
	if (!fd)
	{
		fprintf(stderr, "pool_config: could not open configuration file (%s)\n",
				POOL_CONF_FILE_NAME);
		fprintf(stderr, "pool_config: using default values...\n");
		return 0;
	}

	yyin = fd;
	Lineno = 1;

	while ((token = yylex()))
	{
		if (token == POOL_PARSE_ERROR)
		{
			PARSE_ERROR();
			fclose(fd);
			return(-1);
		}
		if (token == POOL_EOL)
			continue;

		if (token != POOL_KEY)
		{
			PARSE_ERROR();
			fclose(fd);
			return(-1);
		}

		strncpy(key, yytext, sizeof(key));

		pool_debug("key: %s", key);

		token = yylex();

		if (token == POOL_EQUALS)
			token = yylex();

		pool_debug("value: %s kind: %d", yytext, token);

		if (!strcmp(key, "allow_inet_domain_socket") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			/* for backward compatibility */
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			if (v)
				pool_config->listen_addresses = strdup("*");
			else
				pool_config->listen_addresses = strdup("");
		}
		else if (!strcmp(key, "listen_addresses") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->listen_addresses = str;
		}

		else if (!strcmp(key, "port") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 1024)
			{
				pool_error("pool_config: %s must be 1024 or higher numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->port = v;
		}
		else if (!strcmp(key, "pcp_port") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 1024)
			{
				pool_error("pool_config: %s must be 1024 or higher numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->pcp_port = v;
		}
		else if (!strcmp(key, "socket_dir") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->socket_dir = str;
		}
		else if (!strcmp(key, "pcp_socket_dir") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->pcp_socket_dir = str;
		}
		else if (!strcmp(key, "pcp_timeout") &&
			 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be equal or greater or equal to 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->pcp_timeout = v;
		}
		else if (!strcmp(key, "num_init_children") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 1)
			{
				pool_error("pool_config: %s must be higher than 1 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->num_init_children = v;
		}
		else if (!strcmp(key, "child_life_time") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be greater or equal to 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->child_life_time = v;
		}
		else if (!strcmp(key, "client_idle_limit") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be greater or equal to 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->client_idle_limit = v;
		}
		else if (!strcmp(key, "connection_life_time") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be greater or equal to 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->connection_life_time = v;
		}
		else if (!strcmp(key, "child_max_connections") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be greater or equal to 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->child_max_connections = v;
		}
		else if (!strcmp(key, "authentication_timeout") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be higher than 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->authentication_timeout = v;
		}
		else if (!strcmp(key, "max_pool") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be greater or equal to 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->max_pool = v;
		}
		else if (!strcmp(key, "logdir") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->logdir = str;
		}
		else if (!strcmp(key, "pid_file_name") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->pid_file_name = str;
		}
       	else if (!strcmp(key, "log_connections") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->log_connections = v;
		}
       	else if (!strcmp(key, "log_hostname") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->log_hostname = v;
		}
       	else if (!strcmp(key, "enable_pool_hba") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->enable_pool_hba = v;
		}
		else if (!strcmp(key, "backend_socket_dir") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->backend_socket_dir = str;
		}
		else if (!strcmp(key, "replication_mode") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->replication_mode = pool_config->replication_enabled = v;

			if (pool_config->master_slave_enabled && pool_config->replication_enabled)
			{
				pool_error("pool_config: replication_mode and master_slave_mode cannot be enabled at the same time");
				fclose(fd);
				return(-1);
			}

		}
		else if (!strcmp(key, "load_balance_mode") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->load_balance_mode = v;
		}
		else if (!strcmp(key, "replication_stop_on_mismatch") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_debug("replication_stop_on_mismatch: %d", v);
			pool_config->replication_stop_on_mismatch = v;
		}
		else if (!strcmp(key, "replicate_select") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_debug("replicate_select: %d", v);
			pool_config->replicate_select = v;
		}
		else if (!strcmp(key, "reset_query_list") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->reset_query_list = extract_string_tokens(str, ";", &pool_config->num_reset_queries);
			if (pool_config->reset_query_list == NULL)
			{
				fclose(fd);
				return(-1);
			}
		}

		else if (!strcmp(key, "print_timestamp") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->print_timestamp = v;
		}

		else if (!strcmp(key, "master_slave_mode") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->master_slave_mode = pool_config->master_slave_enabled = v;

			if (pool_config->master_slave_enabled && pool_config->replication_enabled)
			{
				pool_error("pool_config: replication_mode and master_slave_mode cannot be enabled at the same time");
				fclose(fd);
				return(-1);
			}
		}

		else if (!strcmp(key, "connection_cache") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->connection_cache = v;
		}

		else if (!strcmp(key, "health_check_timeout") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be equal or higher than 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->health_check_timeout = v;
		}

		else if (!strcmp(key, "health_check_period") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be equal or higher than 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->health_check_period = v;
		}

		else if (!strcmp(key, "health_check_user") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->health_check_user = str;
		}

		else if (!strcmp(key, "failover_command") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->failover_command = str;
		}

		else if (!strcmp(key, "failback_command") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->failback_command = str;
		}

		else if (!strcmp(key, "fail_over_on_backend_error") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->fail_over_on_backend_error = v;
		}

		else if (!strcmp(key, "recovery_user") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->recovery_user = str;
		}

		else if (!strcmp(key, "recovery_password") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->recovery_password = str;
		}

		else if (!strcmp(key, "recovery_1st_stage_command") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->recovery_1st_stage_command = str;
		}

		else if (!strcmp(key, "recovery_2nd_stage_command") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->recovery_2nd_stage_command = str;
		}

		else if (!strcmp(key, "recovery_timeout") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be equal or higher than 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->recovery_timeout = v;
		}

		else if (!strcmp(key, "client_idle_limit_in_recovery") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be greater or equal to 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->client_idle_limit_in_recovery = v;
		}

		else if (!strcmp(key, "insert_lock") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->insert_lock = v;
		}

		else if (!strcmp(key, "ignore_leading_white_space") &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->ignore_leading_white_space = v;
		}

		else if (!strcmp(key, "parallel_mode") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->parallel_mode = v;
		}

		else if (!strcmp(key, "enable_query_cache") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}
			pool_config->enable_query_cache = v;
		}

		else if (!strcmp(key, "pgpool2_hostname") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			if(strlen(str))
				pool_config->pgpool2_hostname = str;
		}

		else if (!strcmp(key, "system_db_hostname") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->system_db_hostname = str;
		}

		else if (!strcmp(key, "system_db_port") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			int v = atoi(yytext);

			if (token != POOL_INTEGER || v < 0)
			{
				pool_error("pool_config: %s must be equal or higher than 0 numeric value", key);
				fclose(fd);
				return(-1);
			}
			pool_config->system_db_port = v;
		}

		else if (!strcmp(key, "system_db_dbname") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->system_db_dbname = str;
		}

		else if (!strcmp(key, "system_db_schema") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->system_db_schema = str;
		}

		else if (!strcmp(key, "system_db_user") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->system_db_user = str;
		}

		else if (!strcmp(key, "system_db_password") && CHECK_CONTEXT(INIT_CONFIG, context))
		{
			char *str;

			if (token != POOL_STRING && token != POOL_UNQUOTED_STRING && token != POOL_KEY)
			{
				PARSE_ERROR();
				fclose(fd);
				return(-1);
			}
			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			pool_config->system_db_password = str;
		}

		else if (!strncmp(key, "backend_hostname", 16) &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context) &&
				 mypid == getpid()) /* this parameter must be modified by parent pid */
		{
			int slot;
			char *str;

			slot = atoi(key + 16);
			if (slot < 0 || slot >= MAX_CONNECTION_SLOTS)
			{
				pool_error("pool_config: backend number %s for backend_hostname out of range", key);
				fclose(fd);
				return(-1);
			}

			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			if (context == INIT_CONFIG ||
				(context == RELOAD_CONFIG && BACKEND_INFO(slot).backend_status == CON_UNUSED))
				strncpy(BACKEND_INFO(slot).backend_hostname, str, MAX_DB_HOST_NAMELEN);
		}

		else if (!strncmp(key, "backend_port", 12) &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context) &&
				 mypid == getpid()) /* this parameter must be modified by parent pid */
		{
			int slot;

			slot = atoi(key + 12);
			if (slot < 0 || slot >= MAX_CONNECTION_SLOTS)
			{
				pool_error("pool_config: host number %s for port number out of range", key);
				fclose(fd);
				return(-1);
			}
			pool_debug("pool_config: port slot number %d ", slot);
			if (context == INIT_CONFIG)
			{
				BACKEND_INFO(slot).backend_port = atoi(yytext);
				BACKEND_INFO(slot).backend_status = CON_CONNECT_WAIT;
			}
			else if (context == RELOAD_CONFIG && BACKEND_INFO(slot).backend_status == CON_UNUSED)
			{
				BACKEND_INFO(slot).backend_port = atoi(yytext);
				BACKEND_INFO(slot).backend_status = CON_DOWN;
			}
		}

		else if (!strncmp(key, "backend_weight", 14) &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context) &&
				 mypid == getpid()) /* this parameter must be modified by parent pid */
		{
			int slot;
			double v;
			BACKEND_STATUS status;

			slot = atoi(key + 14);
			if (slot < 0 || slot >= MAX_CONNECTION_SLOTS)
			{
				pool_error("pool_config: weight number %s for port number out of range", key);
				fclose(fd);
				return(-1);
			}

			v = atof(yytext);

			if (v < 0.0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				fclose(fd);
				return(-1);
			}

			pool_debug("pool_config: weight slot number %d weight: %f", slot, v);
			status = BACKEND_INFO(slot).backend_status;

			if (context == INIT_CONFIG || context == RELOAD_CONFIG)
			{
				double old_v = pool_config->backend_desc->backend_info[slot].unnormalized_weight;
				pool_config->backend_desc->backend_info[slot].unnormalized_weight = v;

				/*
				 * Log weight change event only when context is
				 * reloading of pgpool.conf and weight is actually
				 * changed
				 */
				if (context == RELOAD_CONFIG && old_v != v)
				{
					pool_log("Backend weight for backend%d changed from %f to %f. This will take effect from next client session.", slot, old_v, v);
				}
			}
		}
		else if (!strncmp(key, "backend_data_directory", 22) &&
				 CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context) &&
				 mypid == getpid()) /* this parameter must be modified by parent pid */
		{
			int slot;
			char *str;
			BACKEND_STATUS status;

			slot = atoi(key + 22);
			if (slot < 0 || slot >= MAX_CONNECTION_SLOTS)
			{
				pool_error("pool_config: backend number %s for backend_data_directory out of range", key);
				fclose(fd);
				return(-1);
			}

			str = extract_string(yytext, token);
			if (str == NULL)
			{
				fclose(fd);
				return(-1);
			}
			status = BACKEND_INFO(slot).backend_status;
			if (context == INIT_CONFIG ||
				(context == RELOAD_CONFIG && (status == CON_UNUSED || status == CON_DOWN)))
				strncpy(BACKEND_INFO(slot).backend_data_directory, str, MAX_PATH_LENGTH);
		}
       	else if (!strcmp(key, "log_statement") && CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				return(-1);
			}
			pool_config->log_statement = v;
		}
       	else if (!strcmp(key, "log_per_node_statement") && CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				return(-1);
			}
			pool_config->log_per_node_statement = v;
		}
       	else if (!strcmp(key, "log_statement") && CHECK_CONTEXT(INIT_CONFIG|RELOAD_CONFIG, context))
		{
			int v = eval_logical(yytext);

			if (v < 0)
			{
				pool_error("pool_config: invalid value %s for %s", yytext, key);
				return(-1);
			}
			pool_config->log_statement = v;
		}
	}

	fclose(fd);

	pool_config->backend_desc->num_backends = 0;
	total_weight = 0.0;

	for (i=0;i<MAX_CONNECTION_SLOTS;i++)
	{
		/* port number == 0 indicates that this server is out of use */
		if (BACKEND_INFO(i).backend_port == 0)
		{
			clear_host_entry(i);
		}

		else
		{
			total_weight += BACKEND_INFO(i).unnormalized_weight;
			pool_config->backend_desc->num_backends = i+1;
		}
	}

	pool_debug("num_backends: %d num_backends: %d total_weight: %f",
			   pool_config->backend_desc->num_backends, pool_config->backend_desc->num_backends, total_weight);
	/*
	 * Normalize load balacing weights. What we are doing here is,
	 * assign 0 to RAND_MAX to each backend's weight according to the
	 * value weightN.  For example, if two backends are assigned 1.0,
	 * then each backend will get RAND_MAX/2 normalized weight.
	 */
	for (i=0;i<MAX_CONNECTION_SLOTS;i++)
	{
#ifdef DEBUG
		print_host_entry(i);
#endif

		if (pool_config->backend_desc->backend_info[i].backend_port != 0)
		{
			pool_config->backend_desc->backend_info[i].backend_weight =
				(RAND_MAX) * pool_config->backend_desc->backend_info[i].unnormalized_weight / total_weight;
			pool_debug("backend %d weight: %f", i, pool_config->backend_desc->backend_info[i].backend_weight);
		}
	}

	if (pool_config->parallel_mode || pool_config->enable_query_cache)
	{
		int dist_num;
		SystemDBInfo *info;
		
		system_db_info = malloc(sizeof(POOL_SYSTEMDB_CONNECTION_POOL));
		if (system_db_info == NULL)
		{
			pool_error("failed to allocate sytem_db_info");
			return -1;
		}
		memset(system_db_info, 0, sizeof(*system_db_info));

		system_db_info->system_db_status = pool_shared_memory_create(sizeof(BACKEND_STATUS));
		if (system_db_info->system_db_status == NULL)
		{
			pool_error("failed to allocate system_db_info->system_db_status");
			return -1;
		}
		*system_db_info->system_db_status = CON_CONNECT_WAIT;	/* which is the same as SYSDB_STATUS = CON_CONNECT_WAIT */

		info = malloc(sizeof(SystemDBInfo));
		if (info == NULL)
		{
			pool_error("failed to allocate info");
			return -1;
		}

		system_db_info->info = info;
		info->hostname = pool_config->system_db_hostname;
		info->port = pool_config->system_db_port;
		info->user = pool_config->system_db_user;
		info->password = pool_config->system_db_password;
		info->database_name = pool_config->system_db_dbname;
		info->schema_name = pool_config->system_db_schema;
		info->dist_def_num = 0;
		info->dist_def_slot = NULL;

		if (pool_config->parallel_mode)
		{
			dist_num = pool_memset_system_db_info(info);
			if(dist_num < 0)
			{
				pool_error("failed to get systemdb info");
				return(-1);
			}
		}
		if (pool_config->enable_query_cache)
		{
			info->query_cache_table_info.register_prepared_statement = NULL;
			if (! pool_query_cache_table_exists())
			{
				pool_error("failed to locate query_cache table. perhaps it's not defined?");
				return -1;
			}
		}
		SYSDB_STATUS = CON_UP;
	}

	return 0;
}

static char *extract_string(char *value, POOL_TOKEN token)
{
	char *ret;

	ret = strdup(value);
	if (!ret)
	{
		pool_error("extract_string: out of memory");
		return NULL;
	}

	if (token == POOL_STRING)
	{
		ret[strlen(ret)-1] = '\0';
		return (ret+1);
	}
	return ret;
}

static int eval_logical(char *str)
{
	int ret;

	if (!strcasecmp(str, "true"))
		ret = 1;
	else if (!strcasecmp(str, "false"))
		ret = 0;
	else if (!strcmp(str, "1"))
		ret = 1;
	else if (!strcmp(str, "0"))
		ret = 0;
	else
		ret = -1;

	return ret;
}

/*
 * extract tokens separated by delimi from str. return value is an
 * array of pointers to malloced strings. number of tokens is set to
 * n; note that str will be destroyed by strtok(). Also return value
 * points to static data, that means subsequent call will change the
 * return value.
 */
#define MAXTOKENS 1024
static char **extract_string_tokens(char *str, char *delimi, int *n)
{
	char *token;
	static char *tokens[MAXTOKENS];

	*n = 0;

	for (token = strtok(str, delimi); token != NULL && *n < MAXTOKENS; token = strtok(NULL, delimi))
	{
		tokens[*n] = strdup(token);
		if (tokens[*n] == NULL)
		{
			pool_error("extract_string_tokens: out of memory");
			return NULL;
		}
		pool_debug("extract_string_tokens: token: %s", tokens[*n]);
		(*n)++;
	}
	return tokens;
}

static void clear_host_entry(int slot)
{
	*pool_config->backend_desc->backend_info[slot].backend_hostname = '\0';
	pool_config->backend_desc->backend_info[slot].backend_port = 0;
	pool_config->backend_desc->backend_info[slot].backend_status = CON_UNUSED;
	pool_config->backend_desc->backend_info[slot].backend_weight = 0.0;
}

#ifdef DEBUG
static void print_host_entry(int slot)
{
	pool_debug("slot: %d host: %s port: %d status: %d weight: %f",
			   slot,
			   pool_config->server_hostnames[slot],
			   pool_config->server_ports[slot],
			   pool_config->server_status[slot],
			   pool_config->server_weights[slot]);
}
#endif

