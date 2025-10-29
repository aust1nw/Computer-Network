#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

generic configuration IPForwardingC(){
    provides interface IPForwarding;
}

implementation{
    components new IPForwardingP() as IPFwd;
    IPForwarding = IPFwd.IPForwarding;

    components new LSRoutingC() as LSRouting;
    IPFwd.LSRouting -> LSRouting;

    components ActiveMessageC;
    IPFwd.Packet -> ActiveMessageC;

    components new AMReceiverC(AM_PACK) as IPReceive;
    IPFwd.IPReceive -> IPReceive;

    components new SimpleSendC(AM_PACK) as Send;
    IPFwd.Send -> Send;
}