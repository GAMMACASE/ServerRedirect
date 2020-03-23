#define A2S_GETCHALLENGE	'q'

enum netadrtype_t
{ 
	NA_NULL = 0,
	NA_LOOPBACK,
	NA_BROADCAST,
	NA_IP,
}

enum struct netadr_s_offsets
{
	int type;
	int ip;
	int port;
}

enum struct netpacket_t_offsets
{
	int from;
	//...
	int data;
	//...
	int size;
	//...
}

enum struct NetOffsets
{
	netadr_s_offsets nao;
	netpacket_t_offsets npo;
}
static NetOffsets offsets;

methodmap AddressBase
{
	property Address Address
	{
		public get() { return view_as<Address>(this); }
	}
}

methodmap Netadr_s < AddressBase
{
	property netadrtype_t type
	{
		public get() { return view_as<netadrtype_t>(LoadFromAddress(this.Address + offsets.nao.type, NumberType_Int32)); }
	}
	
	property int ip
	{
		public get() { return LoadFromAddress(this.Address + offsets.nao.ip, NumberType_Int32); }
	}
	
	property int port
	{
		public get() { return LoadFromAddress(this.Address + offsets.nao.port, NumberType_Int16); }
	}
	
	public void ToString(char[] buff, int size)
	{
		int ip = this.ip;
		Format(buff, size, "%i.%i.%i.%i", ip & 0xFF, ip >> 8 & 0xFF, ip >> 16 & 0xFF, ip >>> 24);
	}
}

methodmap Netpacket_t < AddressBase
{
	property Netadr_s from
	{
		public get() { return view_as<Netadr_s>(this.Address + offsets.npo.from); }
	}
	
	//...
	
	property Address data
	{
		public get() { return view_as<Address>(LoadFromAddress(this.Address + offsets.npo.data, NumberType_Int32)); }
	}
	
	//...
	
	property int size
	{
		public get() { return LoadFromAddress(this.Address + offsets.npo.size, NumberType_Int32); }
	}
	
	//...
}

stock void InitNet(GameData gd)
{
	char buff[128];
	
	//netadr_s
	ASSERT_MSG(gd.GetKeyValue("netadr_s::type", buff, sizeof(buff)), "Can't get \"netadr_s::type\" offset from gamedata.");
	offsets.nao.type = StringToInt(buff);
	ASSERT_MSG(gd.GetKeyValue("netadr_s::ip", buff, sizeof(buff)), "Can't get \"netadr_s::ip\" offset from gamedata.");
	offsets.nao.ip = StringToInt(buff);
	ASSERT_MSG(gd.GetKeyValue("netadr_s::port", buff, sizeof(buff)), "Can't get \"netadr_s::port\" offset from gamedata.");
	offsets.nao.port = StringToInt(buff);
	
	//netpacket_t
	ASSERT_MSG(gd.GetKeyValue("netpacket_t::from", buff, sizeof(buff)), "Can't get \"netpacket_t::from\" offset from gamedata.");
	offsets.npo.from = StringToInt(buff);
	offsets.npo.data = gd.GetOffset("netpacket_t::data");
	ASSERT_MSG(offsets.npo.data != -1, "Can't get \"netpacket_t::data\" offset from gamedata");
	offsets.npo.size = gd.GetOffset("netpacket_t::size");
	ASSERT_MSG(offsets.npo.size != -1, "Can't get \"netpacket_t::size\" offset from gamedata");
}