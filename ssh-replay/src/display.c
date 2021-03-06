#include "includes.h"

#include <stdio.h>
#include <mysql.h>
#include <string.h>
#include <ctype.h>
#include <time.h>

#include "log.h"
#include "monitor.h"

typedef struct _monitor_args
{
	int mode;
	char args[4][128];
}MonitorArgs;

extern MonitorArgs margs;
char mysql_address[64];
char mysql_username[64];
char mysql_password[64];
char mysql_database[64];
char display_pl_path[128];
char monitor_pl_path[128];
char telnet_pl_path[128];
char as400_replay_pl_path[128];
//char telnet_client_path[128];

int
parse_monitor_account(const char *str, MonitorArgs *margs)
{
	const char needle[] = "--";
	char * f = strdup(str);
	char * p = f;
	char * t, *buf[8];

	int i, index = 0, ret = 0;

	while(( t = strstr( p, needle ) ) != NULL )
	{
		*t = 0x00;
		buf[index++] = p;
		p = t + strlen( needle );
	} 
	buf[index++] = p;

	for(i = 0; i < index; i++)
	{
		debug("[%s] username = %s", __func__, buf[i]);
	}

	if (strcmp(buf[0], "monitor1") == 0)
	{
		if (index == 3)
		{
			strcpy(margs->args[0], buf[1]);
			strcpy(margs->args[1], buf[2]);
			ret = 1;
		}
		else 
			ret = 0;
	}
	else if (strcmp(buf[0], "monitor2") == 0)
	{
		if (index == 3)
		{
			strcpy(margs->args[0], buf[1]);
			strcpy(margs->args[1], buf[2]);
			if (strcmp(buf[2], "baolei") == 0)
				ret = 4;
			else
				ret = 2;
		}
	}
	else if (strcmp(buf[0], "telnet") == 0)
	{
		if (index == 4)
		{
			strcpy(margs->args[0], buf[1]);
                        strcpy(margs->args[1], buf[2]);
			strcpy(margs->args[2], buf[3]);
			ret = 3;
		}
	}
	else
	{
	}
	margs->mode = ret;
	return ret;
}

/*
   return 0: invalid
   return 1: monitor1-xx-xx
   return 2: monitor2-xx-xx
   return 3: telnet-xx-xx
   return 4: monitor2--id--baolei // replay telnet 
   return 5: monitor1--sid--as400 // replay as400 
 */
int is_monitor_account(char *str, char **radius, int *arg1, int *arg2)
{	
	char *username, *freeptr, *token, needle[] = "--";
	int  display1 = -1, display2 = -1, telnetcl = -1;

	username = strdup(str);
	freeptr  = username;
	token = strstr( username, needle );

	/* add by get radius username */
	if ( token == NULL ) 
	{
		free(freeptr);
		return 0;
	}
	*token = 0x00;
	debug("[%s] radius username = %s", __func__, username);
	if ( *radius != NULL ) strcpy( *radius, username );
	username = token + strlen( needle );
	token = strstr( username, needle );
	
	
	if ( token != NULL )
	{
		*token = '\0';
		display1 = strcmp( username, "monitor1" );
		display2 = strcmp( username, "monitor2" );
		telnetcl = strcmp( username, "telnet" );
		
		/* username is not monitor acct */
		if ( !display1 && !display2 )
		{
			free(freeptr);
			return 0;
		}
		/* username is monitor1-xx-xx */
		else if ( !display1 )
		{
			username = token + strlen( needle );

			/* Get next token: */
			token = strstr( username, needle);

			/* username is monitor1-xx, invalid */
			if ( token == NULL )
			{
				free(freeptr);
				return 0;
			}
			/* username is monitor1-xx-xx */
			else
			{
				*token = '\0';
				*arg1 = atoi(username);
				username = token + strlen( needle );

				/* Get next token: */
				token = strstr( username, needle);

				if ( token == NULL )
				{
					if ( isdigit(*username) )
					{
						*arg2 = atoi(username);
						free(freeptr);
						return 1;
					}
					else if ( strncasecmp( username, "as400", 5 ) == 0 )
					{
						*arg2 = 8964;
						free(freeptr);
						return 5;
					}
				}
				/* username is monitor1-xx-xx-xx, invalid */
				else
				{
					free(freeptr);
					return 0;
				}
			}
		}
		else if ( !display2 )
		{
			username = token + strlen( needle );

			/* Get next token: */
			token = strstr( username, needle);

			/* username is monitor2-xx, invalid */
			if ( token == NULL )
			{
				free(freeptr);
				return 0;
			}
			/* username is monitor2-xx-xx */
			else
			{
				*token = '\0';
				*arg1 = atoi(username);

				username = token + strlen( needle );

				/* Get next token: */
				token = strstr( username, needle);

				if ( token == NULL )
				{
					if ( isdigit(*username) )
					{
						*arg2 = atoi(username);
						free(freeptr);
						return 2;
					}
					else if ( strncasecmp( username, "baolei", 6 ) == 0 )
					{
						*arg2 = 8964;
						free(freeptr);
						return 4;
					}
					/*else if ( strncasecmp( username, "as400", 5 ) == 0 )
					{
						*arg2 = 8964;
						free(freeptr);
						return 5;
					}*/
				}
				/* username is monitor2-xx-xx-xx, invalid */
				else
				{
					free(freeptr);
					return 0;
				}
			}
		}
		else if ( !telnetcl )
		{
			username = token + strlen( needle );

			/* Get next token: */
			token = strstr( username, needle);

			/* username is telnet-xx, invalid */
			if ( token == NULL )
			{
				free(freeptr);
				return 0;
			}
			/* username is telnet-xx-xx */
			else
			{
				*token = '\0';
				*arg1 = atoi(username);

				username = token + strlen( needle );

				/* Get next token: */
				token = strstr( username, needle);

				if ( token == NULL )
				{
					*arg2 = atoi(username);
					free(freeptr);
					if ( get_luser_from_mysql(*arg1,*arg2) == 1 )
						return 3;
					else
						return 0;
				}
				/* username is telnet-xx-xx-xx, invalid */
				else
				{
					free(freeptr);
					return 0;
				}
			}
		}
	}
	else
	{
		free(freeptr);
		return 0;
	}
}

char * get_replay_filename()
{
	static MYSQL *radius_sql_conn;
	static MYSQL_RES *query_result;
	static MYSQL_ROW row;
	static int query;
	static char buf[256], * p1, * p2;
	unsigned int num_fields;
	MYSQL_FIELD *fileds;

	radius_sql_conn = mysql_init(NULL);
	radius_sql_conn = mysql_real_connect( radius_sql_conn, mysql_address, mysql_username, mysql_password, mysql_database, 0, NULL, 0 );
	snprintf( buf, sizeof(buf), "SELECT * FROM sessions WHERE sid = %s", margs.args[0] );

	query = mysql_query( radius_sql_conn, buf );
	//if (query_error!=0)//do error

	query_result = mysql_store_result( radius_sql_conn );

	num_fields = mysql_num_fields(query_result);
	fileds = mysql_fetch_fields(query_result);
	while ((row=mysql_fetch_row(query_result))!=NULL)
	{
		debug("%s\n", row[9]);
		memset( buf, 0x00, sizeof(buf) );
		p1 = strchr( row[9], '"' );
		if (p1 != NULL) {
			*p1 = '\0';
			strcat ( buf, row[9] );
			p2 = strchr( p1+1, '"' );
			*p2 = '\0';
			strcat ( buf, p1+1 );
		}
		else 
			strcpy(buf, row[9]);
		debug("%s\n", buf);
	}
	mysql_close(radius_sql_conn);
	return buf;
}

char * get_as400_replay_filename()
{
	static MYSQL *radius_sql_conn;
	static MYSQL_RES *query_result;
	static MYSQL_ROW row;
	static int query;
	static char buf[256], * p1, * p2;
	unsigned int num_fields;
	MYSQL_FIELD *fileds;

	radius_sql_conn = mysql_init(NULL);
	radius_sql_conn = mysql_real_connect( radius_sql_conn, mysql_address, mysql_username, mysql_password, mysql_database, 0, NULL, 0 );
	snprintf( buf, sizeof(buf), "SELECT replayfile FROM AS400_sessions WHERE sid = %s", margs.args[0] );

	query = mysql_query( radius_sql_conn, buf );
	//if (query_error!=0)//do error

	query_result = mysql_store_result( radius_sql_conn );
	row = mysql_fetch_row(query_result);
	bzero( buf, sizeof(buf) );
	if ( row && row[0] ) strcpy( buf, row[0] );
	mysql_close(radius_sql_conn);
	return buf;
}

long int get_replay_systemtime()
{
	struct tm tm_time;
	time_t t_day;

	static MYSQL *radius_sql_conn;
	static MYSQL_RES *query_result;
	static MYSQL_ROW row;
	static int query;
	static char buf[256], * p1, * p2;
	unsigned int num_fields;
	MYSQL_FIELD *fileds;

	radius_sql_conn = mysql_init(NULL);
	radius_sql_conn = mysql_real_connect( radius_sql_conn, mysql_address, mysql_username, mysql_password, mysql_database, 0, NULL, 0 );
	snprintf( buf, sizeof(buf), "SELECT * FROM commands WHERE cid = %s", margs.args[1] );

	query = mysql_query( radius_sql_conn, buf );

	query_result = mysql_store_result( radius_sql_conn );

	num_fields = mysql_num_fields(query_result);
	fileds = mysql_fetch_fields(query_result);
	while ((row=mysql_fetch_row(query_result))!=NULL)
	{
		debug("commands at %s", row[2]);
		p1 = row[2];
		p2 = strchr(p1,'-');
		*p2 = 0x00;
		tm_time.tm_year = atoi(p1) - 1900;

		p1 = p2+1;
		p2 = strchr(p1,'-');
		*p2 = 0x00;
		tm_time.tm_mon = atoi(p1) - 1;

		p1 = p2+1;
		p2 = strchr(p1,' ');
		*p2 = 0x00;
		tm_time.tm_mday = atoi(p1);

		p1 = p2+1;
		p2 = strchr(p1,':');
		*p2 = 0x00;
		tm_time.tm_hour = atoi(p1);

		p1 = p2+1;
		p2 = strchr(p1,':');
		*p2 = 0x00;
		tm_time.tm_min = atoi(p1);

		p1 = p2+1;
		tm_time.tm_sec = atoi(p1);

		tm_time.tm_isdst = 0;
	}

	t_day = mktime(&tm_time);
	debug("ctime = %s, long = %ld", ctime(&t_day), t_day);
	mysql_close(radius_sql_conn);
	return t_day;
}

int get_luser_from_mysql( int device_table_id, int memberid )
{
	static MYSQL *radius_sql_conn;
	static MYSQL_RES *query_result;
	static MYSQL_ROW row;
	static int query;
	static char buf[4096];
	static char luserid[256], lgroupid[256], gid[256];
	static char *token;

	radius_sql_conn = mysql_init(NULL);
	radius_sql_conn = mysql_real_connect( radius_sql_conn, mysql_address, mysql_username, mysql_password, mysql_database, 0, NULL, 0 );

	snprintf( buf, sizeof(buf), "SELECT luser,lgroup FROM devices WHERE id = %d", device_table_id );
	query = mysql_query( radius_sql_conn, buf );
	query_result = mysql_store_result( radius_sql_conn );
	row = mysql_fetch_row(query_result);
	
	if ( row && row[0] ) strcpy( luserid,  row[0] );
	if ( row && row[1] ) strcpy( lgroupid, row[1] );
	
	debug( "[%s] luserid in devices = %s\n", __func__, luserid );
	token = strtok( luserid, ",");
	while ( token != NULL )
	{
		/* While there are tokens in "string" */
		if ( atoi(token) == memberid )
		{
			mysql_close(radius_sql_conn);
			return 1;
		}
		/* Get next token: */
		token = strtok( NULL, ",");
	}

	snprintf( buf, sizeof(buf), "SELECT groupid FROM member WHERE uid = %d", memberid );
	query = mysql_query( radius_sql_conn, buf );
	query_result = mysql_store_result( radius_sql_conn );
	row = mysql_fetch_row(query_result);

	if ( row && row[0] ) strcpy( gid,  row[0] );

	debug( "[%s] groupid in member = %s, lgroup in devices = %s\n", __func__, gid, lgroupid );
	token = strtok( lgroupid, ",");
	while ( token != NULL )
	{
		if ( strcmp(token,gid) == 0 )
		{
			mysql_close(radius_sql_conn);
			return 1;
		}
		token = strtok( NULL, ",");
	}

	mysql_close(radius_sql_conn);
	return 0;
}
