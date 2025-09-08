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
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP;
}