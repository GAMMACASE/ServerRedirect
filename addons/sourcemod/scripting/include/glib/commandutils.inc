#if defined _commandutils_included
#endinput
#endif
#define _commandutils_included

#define MAX_CMD_LENGTH 128

static ArrayList gRegisteredCommands;

//Accepts string of commands separated by a semicolon
stock void RegConsoleCmds(const char[] commands, ConCmd callback, const char[] description = "", int flags = 0)
{
	if(!gRegisteredCommands)
		gRegisteredCommands = new ArrayList(ByteCountToCells(MAX_CMD_LENGTH));
	
	ArrayList arr = new ArrayList(ByteCountToCells(MAX_CMD_LENGTH));
	
	char buff[MAX_CMD_LENGTH];
	int start_pos, len;
	bool shouldskip;
	for(int i = 0; commands[i] != '\0'; start_pos = i++)
	{
		buff[0] = '\0';
		
		do
		{
			if((!IsCharAlpha(commands[i]) && !IsCharNumeric(commands[i]) && commands[i] != '_') || i - start_pos + 1 >= MAX_CMD_LENGTH)
			{
				len = FindCharInString(commands[i], ';');
				if(len == -1)
					i = start_pos + strlen(commands[start_pos]);
				else
					i += len;
				
				len = i++ - start_pos + 1;
				char[] tempbuff = new char[len + 1];
				strcopy(tempbuff, len, commands[start_pos]);
				LogError("Failed to create command \"%s\".", tempbuff);
				
				shouldskip = true;
				break;
			}
		}
		while(commands[++i] != ';' && commands[i] != '\0');
		
		if(shouldskip)
			continue;
		
		len = i++ - start_pos + 1;
		strcopy(buff, (len > MAX_CMD_LENGTH ? MAX_CMD_LENGTH : len), commands[start_pos]);
		
		PrintToServer("Registering \"%s\"", buff);
		
		if(gRegisteredCommands.FindString(buff) == -1)
			RegConsoleCmd(buff, callback, description, flags);
		
		arr.PushString(buff);
	}
	
	delete gRegisteredCommands;
	gRegisteredCommands = arr.Clone();
	
	delete arr;
}

stock bool IsValidCmd()
{
	char buff[MAX_CMD_LENGTH];
	GetCmdArg(0, buff, sizeof(buff));
	
	return gRegisteredCommands.FindString(buff) != -1;
}