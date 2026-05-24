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
    LSR.ND -> ND.NeighborDiscovery;

    components new FloodingC() as Flooding;
    LSR.Flooding -> Flooding;

    components new TimerMilliC() as LSATimer;
    LSR.LSATimer -> LSATimer;

    components new TimerMilliC() as computeTimer;
    LSR.computeTimer -> computeTimer;

    components RandomC as Random;
    LSR.Random -> Random;

    components new HashmapC(route_entry, 20) as RoutingTable;
    LSR.RoutingTable -> RoutingTable;

    components new GraphC() as Graph;
    LSR.Graph -> Graph;

    components new PoolC(LSA, 255) as LSAPool;
    components new QueueC(LSA*, 255) as LSAQueue;

    LSR.LSAPool -> LSAPool;
    LSR.LSAQueue -> LSAQueue;
}