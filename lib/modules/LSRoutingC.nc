#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/LSA.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channels.h"

generic configuration LSRoutingC(){
    provides interface LSRouting;
}

implementation{
    components new LSRoutingP() as LSR;
    LSRouting = LSR.LSRouting;

    components new NeighborDiscoveryC() as ND;
    LSR.ND -> ND;

    components new FloodingC() as Flooding;
    LSR.Flooding -> Flooding;

    components new TimerMilliC() as LSATimer;
    LSR.LSATimer -> LSATimer;

    components new HashmapC(route_entry, 20) as RoutingTable;
    LSR.RoutingTable -> RoutingTable;

    components new GraphC() as Graph;
    LSR.Graph -> Graph;
}