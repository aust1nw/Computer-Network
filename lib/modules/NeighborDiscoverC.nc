#include <Timer.h>
#include "../../includes/command.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendinfo.h"
#include "../../includes/channel.h"

configuration NeighborDiscoveryC{
    provides interface NeighborDiscover;
}

implementation{
    components new NeighborDiscoverP();
    NeighborDiscovery = NeighborDiscoverP.NeighborDiscover;

    components new TimerMilliC() as Timer1;
    components new RandomC as Random;
    
    NeighborDiscoverP.neighborTimer -> Timer1;
    NeighborDiscoverP.Random -> Random;
}