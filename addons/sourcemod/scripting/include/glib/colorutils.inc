#if defined _colorutils_included
#endinput
#endif
#define _colorutils_included

#define CLR_D	"\1" //COLOR_DEFAULT
#define CLR_R	"\2" //COLOR_RED
#define CLR_LP	"\3" //COLOR_LIGHTPURPLE
#define CLR_GRN	"\4" //COLOR_GREEN
#define CLR_L	"\5" //COLOR_LIME
#define CLR_LG	"\6" //COLOR_LIGHTGREEN
#define CLR_LR	"\7" //COLOR_LIGHTRED
#define CLR_GRY	"\8" //COLOR_GRAY
#define CLR_LO	"\9" //COLOR_LIGHTOLIVE
#define CLR_M	"\10" //COLOR_METAL
#define CLR_LB	"\11" //COLOR_LIGHTBLUE
#define CLR_B	"\12" //COLOR_BLUE
#define CLR_P	"\13" //COLOR_PURPLE
#define CLR_V	"\14" //COLOR_VIOLET
#define CLR_R2	"\15" //COLOR_RED2
#define CLR_G	"\16" //COLOR_GOLD

static char gColorNames[][] = {"{DEFAULT}", "{RED}", "{LIGHTPURPLE}", "{GREEN}", "{LIME}", "{LIGHTGREEN}", "{LIGHTRED}", "{GRAY}", "{LIGHTOLIVE}", "{METAL}", "{LIGHTBLUE}", "{BLUE}", "{PURPLE}", "{VIOLET}", "{RED2}", "{GOLD}"},
	gShortColorNames[][] = {"{D}", "{R}", "{LP}", "{GRN}", "{L}", "{LG}", "{LR}", "{GRY}", "{LO}", "{M}", "{LB}", "{B}", "{P}", "{V}", "{R2}", "{G}"},
	gColorCodes[][] = {CLR_D, CLR_R, CLR_LP, CLR_GRN, CLR_L, CLR_LG, CLR_LR, CLR_GRY, CLR_LO, CLR_M, CLR_LB, CLR_B, CLR_P, CLR_V, CLR_R2, CLR_G};

enum 
{
	COLOR_START = 1,
	COLOR_DEFAULT = 1,
	COLOR_RED = 2,
	COLOR_LIGHTPURPLE,
	COLOR_GREEN,
	COLOR_LIME,
	COLOR_LIGHTGREEN,
	COLOR_LIGHTRED,
	COLOR_GRAY,
	COLOR_LIGHTOLIVE,
	COLOR_U1,
	COLOR_LIGHTBLUE,
	COLOR_BLUE,
	COLOR_U2,
	COLOR_PURPLE,
	COLOR_DARKORANGE,
	COLOR_GOLD,
	COLOR_END = COLOR_GOLD
}

#if defined CUSTOM_CHAT_FUNCS
#define MAX_MESSAGE_LENGTH 2512

stock void PrintToChatGeneric(int client, const char[] msg, bool chat = true)
{
	Protobuf pb = view_as<Protobuf>(StartMessageOne("SayText", client, USERMSG_RELIABLE));
	
	pb.SetInt("ent_idx", 0);
	pb.SetBool("chat", chat);
	pb.SetString("text", msg);
	
	EndMessage();
}

stock void PrintToChatAllGeneric(const char[] msg, bool chat = true)
{
	Protobuf pb = view_as<Protobuf>(StartMessageAll("SayText", USERMSG_RELIABLE));
	
	pb.SetInt("ent_idx", 0);
	pb.SetBool("chat", chat);
	pb.SetString("text", msg);
	
	EndMessage();
}
#else
#define MAX_MESSAGE_LENGTH 512
#define PrintToChatGeneric PrintToChat
#define PrintToChatAllGeneric PrintToChatAll
#endif

stock void PrintToChatColored(int client, const char[] format, any ...)
{
	char buff[MAX_MESSAGE_LENGTH];
	VFormat(buff, sizeof(buff), format, 3);
	
	ReformatMessage(buff, sizeof(buff));
	CheckForSpace(buff, sizeof(buff));
	
	PrintToChatGeneric(client, buff);
}

stock void PrintToChatAllColored(const char[] format, any ...)
{
	char buff[MAX_MESSAGE_LENGTH];
	VFormat(buff, sizeof(buff), format, 2);
	
	ReformatMessage(buff, sizeof(buff));
	CheckForSpace(buff, sizeof(buff));
	
	PrintToChatAllGeneric(buff);
}

stock void ReformatMessage(char[] buff, int len)
{
	for(int i = 0; i < COLOR_END; i++)
	{
		ReplaceString(buff, len, gColorNames[i], gColorCodes[i], false);
		ReplaceString(buff, len, gShortColorNames[i], gColorCodes[i], false);
	}
}

stock void CheckForSpace(char[] buff, int len)
{
	if(COLOR_START < buff[0] < COLOR_END)
		Format(buff, len, " %s", buff);
}