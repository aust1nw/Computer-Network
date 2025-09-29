#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/neighborEntry.h"

generic configuration FloodingC(){
    provides interface Flooding;
}

implementation{
    components new FloodingP() as Flood;
    Flooding = Flood.Flooding;

    components new TimerMilliC() as FloodingTimer;
    Flood.FloodingTimer -> FloodingTimer;

    components RandomC as Random;
    Flood.Random -> Random;

    components ActiveMessageC;
    Flood.Packet -> ActiveMessageC;

    components new HashmapC(NeighborEntry, 20) as NeighborTable;
    Flood.NeighborTable -> NeighborTable;

    components new SimpleSendC(AM_PACK) as Send;
    Flood.Send -> Send;

    components new NeighborDiscoveryC();
    Flood.NeighborDiscovery -> NeighborDiscoveryC;
}
