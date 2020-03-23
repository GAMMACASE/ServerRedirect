#if defined _server_redirect_included
#endinput
#endif
#define _server_redirect_included

/**
 * Redirects client to a specific ip address.
 *
 * Note: Client will be disconnected during redirecting process, so all 
 * disconnect forwards/events will be called too.
 *
 * @param client        Client index.
 * @param ip            Full ip address, can also be a format string.
 *                      Server ip will not be validated, you should validate it
 *                      yourself, or else player connection will be dropped
 *                      due to invalid ip address. (Expected format: XXX.XXX.XXX.XXX:XXXXX)
 * @param ...           Variable number of format parameters.
 * @error               Invalid client.
 */
native void RedirectClient(int client, char[] ip, any ...);


//Plugin dependency

public SharedPlugin __pl_server_redirect = 
{
	name = "server_redirect",
	file = "server_redirect.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_server_redirect_SetNTVOptional()
{
	MarkNativeAsOptional("RedirectClient");
}
#endif