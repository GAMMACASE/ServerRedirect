StringMap gShouldReconnect;
Handle gRejectConnection;

void SetupSDKCalls(GameData gd)
{
	//CBaseServer::RejectConnection
	StartPrepSDKCall(SDKCall_Static);
	
	ASSERT_MSG(PrepSDKCall_SetFromConf(gd, SDKConf_Signature, "CBaseServer::RejectConnection"), "Can't get offset for \"CBaseServer::RejectConnection\".");
	
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	
	gRejectConnection = EndPrepSDKCall();
	ASSERT_MSG(gRejectConnection, "Failed to create SDKCall to \"CBaseServer::RejectConnection\".");
}

void SetupDhooks(GameData gd)
{
	//CBaseServer::ProcessConnectionlessPacket
	Handle dhook = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Bool, ThisPointer_Address);
	
	ASSERT_MSG(DHookSetFromConf(dhook, gd, SDKConf_Signature, "CBaseServer::ProcessConnectionlessPacket"), "Can't find \"CBaseServer::ProcessConnectionlessPacket\" signature.");
	DHookAddParam(dhook, HookParamType_Int);
	
	ASSERT_MSG(DHookEnableDetour(dhook, false, ProcessConnectionlessPacket_Dhook), "Can't enable detour for \"CBaseServer::ProcessConnectionlessPacket\".");
}

public MRESReturn ProcessConnectionlessPacket_Dhook(Address pThis, Handle hReturn, Handle hParams)
{
	if(gShouldReconnect.Size == 0)
		return MRES_Ignored;
	
	Netpacket_t packet = DHookGetParam(hParams, 1);
	
	if(packet.size < 5)
		return MRES_Ignored;
	
	if(LoadFromAddress(packet.data + 4, NumberType_Int8) != A2S_GETCHALLENGE)
		return MRES_Ignored;
	
	Netadr_s from = packet.from;
	
	if(from.type != NA_IP)
		return MRES_Ignored;
	
	char buff[32], buff2[64];
	from.ToString(buff, sizeof(buff));
	
	if(gShouldReconnect.GetString(buff, buff2, sizeof(buff2)))
	{
		gShouldReconnect.Remove(buff);
		
		RejectConnection(pThis, packet, "ConnectRedirectAddress:%s", buff2);
		
		DHookSetReturn(hReturn, 1);
		return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

stock void RejectConnection(Address pThis, Netpacket_t packet, const char[] reject_msg, any ...)
{
	char buff[64];
	VFormat(buff, sizeof(buff), reject_msg, 4);
	SDKCall(gRejectConnection, pThis, packet, buff);
}

public any RedirectClient_Native(Handle plugin, int numParams)
{
	char buff[32];
	FormatNativeString(0, 2, 3, sizeof(buff), .out_string = buff);
	RedirectClient(GetNativeCell(1), buff);
}

stock void RedirectClient(int client, const char[] ip)
{
	char buff[32];
	GetClientIP(client, buff, sizeof(buff));
	gShouldReconnect.SetString(buff, ip);
	ClientCommand(client, "retry");
}